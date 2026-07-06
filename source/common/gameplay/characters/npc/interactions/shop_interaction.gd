class_name ShopInteraction
extends NPCInteraction
## NPC capability: opens a shop. The catalog renders client-side from the
## ShopResource carried in the menu arg; the server authorizes purchases by
## resolving the shop from the player's current map, keyed by the owning NPC's
## giver_key() (its NPCResource filename slug) — so an inline shop on an NPC
## works with no registry id and no plugin index, the same way quests resolve.

@export var shop: ShopResource


func menu_entry(npc: Node) -> Dictionary:
	var owner: NPC = npc as NPC
	if shop == null or owner == null:
		return {}
	# The ShopResource rides in the arg so the client renders the catalog
	# directly (no load-by-id); the key authorizes purchases server-side.
	return {
		"label": _label_or("Shop"),
		"icon": _icon_or(""),
		"menu": &"shop",
		"arg": {"key": String(_shop_key(owner)), "shop": shop},
	}


func register(map: Map, npc: Node) -> void:
	var owner: NPC = npc as NPC
	if shop and owner != null:
		var key: StringName = _shop_key(owner)
		# Two shop NPCs resolving to the same key with different shops collide and the
		# last write silently wins. Warn the author rather than fail silently.
		if map.shops.has(key) and map.shops[key] != shop:
			push_warning("ShopInteraction: duplicate shop key '%s' — two shop NPCs resolve to the same key; one will be unreachable. Give them distinct NPCResource files or node names." % key)
		map.shops[key] = shop
		# Boot-time visibility: one line per registered shop, so a mis-keyed or
		# missing merchant is diagnosable from the world log instead of a dead Buy.
		# Server-only by construction (npc.gd gates register() on is_server()).
		ServerLog.info("Shop registered: '%s' -> \"%s\" (map %s)" % [key, shop.shop_name, map.name])


## The map-unique key this shop registers + authorizes under. Prefer the NPC's
## giver_key (its NPCResource file slug); fall back to the NPC's node name when
## the resource is INLINE (no file -> empty slug), so inline shop NPCs get a
## stable, collision-free key instead of every inline shop sharing "". Node names
## are unique per scene — the same basis crafting stations key on. menu_entry
## (client arg) and register (server map) both call this, so they always agree.
static func _shop_key(owner: NPC) -> StringName:
	var key: StringName = owner.giver_key()
	return key if not key.is_empty() else owner.name
