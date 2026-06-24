class_name RedeemCodes
## Server-only registry of redeem codes + their reward bundles, plus the apply
## logic. Per-character redemption tracking lives on PlayerResource.redeemed_codes;
## this class only knows the codes themselves. Full design: docs/redeem_codes.md.
##
## SECURITY — why the code table is a function BODY, not a const: the tinymmo
## export plugin replaces every source/server/*.gd with a reflection stub on
## CLIENT exports (faithful consts, push_error bodies). A const would be copied
## faithfully and LEAK every code into shipped client builds; a function body is
## stripped to push_error, so the codes never ship. Edit codes in _table() below.
## (The class is also server-only, so the client never calls this at all.)
##
## A grant is one of:
##   {"type": "currency", "amount": int}            gold (Economy.gold_id())
##   {"type": "item",     "id": int, "amount": int}
##   {"type": "title",    "title": String}
##   {"type": "skin",     "id": int}                cosmetic (owned_skins)
##   {"type": "xp",       "amount": int}
## A code entry: {"note": String, "expires_at": int (unix-s, 0 = never),
##   "max_uses": int (-1 = ∞; NOT enforced in per-character v1), "grants": Array}.

## Reward discipline (owner rule): codes grant ONLY minimal, non-tradable things —
## starter-scale currency, non-tradable consumables, account-bound cosmetics/titles.
## That's what makes per-character tracking safe (nothing worth farming/funneling).

static var _cache: Dictionary = {}


## The authored code table. Keys are matched case-insensitively (stored UPPER).
## Body intentional — see class docstring (stripped from client exports).
static func _table() -> Dictionary:
	return {
		"EMBERFOUNDER": {
			"note": "Alpha-tester thank-you. Universal, no expiry.",
			"grants": [
				{"type": "title", "title": "Ember Founder"},
				{"type": "skin", "id": 24},  # royal_knight — keep OUT of the wardrobe shop for true exclusivity
				{"type": "currency", "amount": 100},
			],
		},
		"WELCOME": {
			"note": "New-player starter gift.",
			"grants": [
				{"type": "currency", "amount": 50},
				{"type": "item", "id": 1, "amount": 3},  # Health Potion
			],
		},
		"HEARTHKEEPER": {
			"note": "Discord / community milestone.",
			"grants": [
				{"type": "title", "title": "Hearthkeeper"},
				{"type": "skin", "id": 29},  # scholar_director
			],
		},
		"STREAMDROP": {
			"note": "Example marketing code — dated/capped shape (max_uses not enforced in v1).",
			"expires_at": 0,
			"max_uses": 5000,
			"grants": [
				{"type": "currency", "amount": 25},
			],
		},
	}


## Looks up a code (case-insensitive, trimmed). Returns {} if not found.
static func get_code(code: String) -> Dictionary:
	if _cache.is_empty():
		_cache = _table()
	return _cache.get(code.strip_edges().to_upper(), {})


## True if the entry has an expiry in the past. max_uses is intentionally NOT
## checked here — a global cap needs a shared counter the per-character v1 lacks
## (see docs/redeem_codes.md).
static func is_expired(entry: Dictionary) -> bool:
	var expires_at: int = int(entry.get("expires_at", 0))
	return expires_at > 0 and Time.get_unix_time_from_system() >= expires_at


## Validates EVERY grant before any is applied, so a misconfigured code can never
## half-grant. Returns false on any malformed or unresolvable grant.
static func validate_grants(grants: Array) -> bool:
	for g: Variant in grants:
		if not (g is Dictionary):
			return false
		var grant: Dictionary = g
		match str(grant.get("type", "")):
			"currency":
				if int(grant.get("amount", 0)) <= 0 or Economy.gold_id() <= 0:
					return false
			"item":
				if int(grant.get("amount", 0)) <= 0:
					return false
				if ContentRegistryHub.load_by_id(&"items", int(grant.get("id", 0))) == null:
					return false
			"xp":
				if int(grant.get("amount", 0)) <= 0:
					return false
			"title":
				if str(grant.get("title", "")).strip_edges().is_empty():
					return false
			"skin":
				if not PlayerSkins.is_valid(int(grant.get("id", 0))):
					return false
			_:
				return false
	return true


## Applies a pre-validated bundle to the character, mutating PlayerResource in
## place. Returns reward descriptors for the client (see _grant_descriptor). No
## explicit save: the grants AND the redeemed-code record live on the same
## PlayerResource, so the world's periodic save persists them atomically. A crash
## before that loses both together — the player just redeems again, no dupes.
static func apply_grants(pr: PlayerResource, grants: Array) -> Array:
	var rewards: Array = []
	for g: Variant in grants:
		var grant: Dictionary = g
		match str(grant.get("type", "")):
			"currency":
				Inventory.add_item(pr.inventory, Economy.gold_id(), int(grant.get("amount", 0)))
			"item":
				Inventory.add_item(pr.inventory, int(grant.get("id", 0)), int(grant.get("amount", 0)))
			"xp":
				pr.add_experience(int(grant.get("amount", 0)))
			"title":
				var title: String = str(grant.get("title", "")).strip_edges()
				if not pr.titles_unlocked.has(title):
					pr.titles_unlocked.append(title)
					if pr.display_title.is_empty():
						pr.display_title = title
			"skin":
				var skin_id: int = int(grant.get("id", 0))
				if not pr.owned_skins.has(skin_id):
					pr.owned_skins.append(skin_id)
		rewards.append(_grant_descriptor(grant))
	return rewards


## Resolves a bundle to display descriptors WITHOUT granting — lets mail preview
## its attachments before they're claimed. Same shape apply_grants returns.
static func describe_grants(grants: Array) -> Array:
	var out: Array = []
	for g: Variant in grants:
		if g is Dictionary:
			out.append(_grant_descriptor(g))
	return out


## One grant → {"type", "name", "amount"} for the client (name resolved from the
## item / skin registries). Pure: no mutation, so apply and preview agree.
static func _grant_descriptor(grant: Dictionary) -> Dictionary:
	match str(grant.get("type", "")):
		"currency":
			return {"type": "currency", "name": "Gold", "amount": int(grant.get("amount", 0))}
		"item":
			var item: Item = ContentRegistryHub.load_by_id(&"items", int(grant.get("id", 0))) as Item
			return {"type": "item", "name": String(item.item_name) if item != null else "Item", "amount": int(grant.get("amount", 0))}
		"xp":
			return {"type": "xp", "name": "XP", "amount": int(grant.get("amount", 0))}
		"title":
			return {"type": "title", "name": str(grant.get("title", "")).strip_edges(), "amount": 1}
		"skin":
			return {"type": "skin", "name": PlayerSkins.display_name(int(grant.get("id", 0))), "amount": 1}
		_:
			return {"type": "unknown", "name": "Reward", "amount": 1}
