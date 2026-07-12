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
		# register_keyed carries the duplicate-key warning (the guild-house bug class).
		map.register_keyed(map.shops, key, shop, "shop")
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
