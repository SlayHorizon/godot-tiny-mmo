class_name ShopResource
extends Resource
## Editor-authored shop definition, registered as the "shops" content type.
##
## Workflow: create instances under res://source/common/gameplay/shops/data/,
## then run the TinyMMO plugin's Generate with content_name "shops" pointing at
## that folder. The plugin assigns each shop a registry id/slug (baked into
## metadata) and builds shops_index.tres, so shops resolve through
## ContentRegistryHub like items and maps — sent over the network as a small id.

@export var shop_name: String
@export var entries: Array[ShopEntry]


## Loads a shop by its registry id, or null if the shops content type hasn't been
## generated yet / the id is unknown.
static func load_shop(shop_id: int) -> ShopResource:
	if ContentRegistryHub.registry_of(&"shops") == null:
		return null
	return ContentRegistryHub.load_by_id(&"shops", shop_id) as ShopResource


## { "price": int, "currency": int } for one item, or {} if not sold here.
func entry_for(item_id: int) -> Dictionary:
	for entry: ShopEntry in entries:
		if entry and entry.item and int(entry.item.get_meta(&"id", 0)) == item_id:
			return {"price": entry.price, "currency": entry.currency}
	return {}
