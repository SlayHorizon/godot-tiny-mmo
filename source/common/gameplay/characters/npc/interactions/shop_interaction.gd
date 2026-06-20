class_name ShopInteraction
extends NPCInteraction
## NPC capability: opens a shop. The catalog renders client-side from the
## ShopResource; the server authorizes purchases by the shop's registry id.

@export var shop: ShopResource


func menu_entry(_npc: Node) -> Dictionary:
	if shop == null:
		return {}
	return {
		"label": _label_or("Shop"),
		"icon": _icon_or(""),
		"menu": &"shop",
		"arg": int(shop.get_meta(&"id", 0)),
	}


func register(map: Map, _npc: Node) -> void:
	if shop:
		map.shops[int(shop.get_meta(&"id", 0))] = shop
