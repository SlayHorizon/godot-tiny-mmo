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
		"arg": {"key": String(owner.giver_key()), "shop": shop},
	}


func register(map: Map, npc: Node) -> void:
	var owner: NPC = npc as NPC
	if shop and owner != null:
		map.shops[owner.giver_key()] = shop
