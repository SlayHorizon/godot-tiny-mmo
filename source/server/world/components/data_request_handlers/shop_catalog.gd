class_name ShopCatalog


# { shop_id -> { item_id -> price } }
const CATALOGS: Dictionary = {
	&"default": {
		1: 5,   # health_potion
		2: 20,  # copper_ring
		5: 30,  # wooden_bow.item
		11: 15, # cloth_hood
		12: 25, # cloth_vest
		16: 20, # heavy_boots
		18: 40, # iron_chest
		19: 35, # iron_helmet
	}
}


static func get_price(shop_id: StringName, item_id: int) -> int:
	return (CATALOGS.get(shop_id, {}) as Dictionary).get(item_id, -1)


static func get_items(shop_id: StringName) -> Dictionary:
	return CATALOGS.get(shop_id, {}) as Dictionary
