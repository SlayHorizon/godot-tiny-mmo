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


## The map-unique key this shop registers + authorizes under. Base = the NPC's
## giver_key (its NPCResource file slug), falling back to the NPC's node name for
## INLINE resources (no file -> empty slug). The SHOP's slug is appended when it
## has one, so an NPC carrying MULTIPLE ShopInteractions (the all-sets test
## merchant) gets one collision-free key per shop instead of them all fighting
## over the NPC key. menu_entry (client arg) and register (server map) both call
## this, so they always agree.
func _shop_key(owner: NPC) -> StringName:
	var base: StringName = owner.giver_key()
	if base.is_empty():
		base = owner.name
	var shop_slug: String = String(shop.get_meta(&"slug", "")) if shop != null else ""
	if shop_slug.is_empty():
		return base
	return StringName("%s:%s" % [base, shop_slug])
