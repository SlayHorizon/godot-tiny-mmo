class_name ShopResource
extends Resource
## Editor-authored shop definition, registered as the "shops" content type.
##
## Workflow: create instances under res://source/common/gameplay/shops/data/,
## then run the TinyMMO plugin's Generate with content_name "shops" pointing at
## that folder. The plugin assigns each shop a registry id/slug (baked into
## metadata) and builds shops_index.tres, so shops resolve through
## ContentRegistryHub like items and maps — sent over the network as a small id.

## Which trades this shop offers the player (controls which tabs the shop UI shows).
enum Trades {
	BUY_ONLY,  ## Player can only buy from this shop (only the Buy tab is shown).
	SELL_ONLY, ## Player can only sell to this shop (only the Sell tab is shown).
	BOTH,      ## Player can buy and sell (both tabs shown).
}

@export var shop_name: String
@export var entries: Array[ShopEntry]
@export var trades: Trades = Trades.BOTH


## Loads a shop by its registry id, or null if the shops content type hasn't been
## generated yet / the id is unknown.
static func load_shop(shop_id: int) -> ShopResource:
	if ContentRegistryHub.registry_of(&"shops") == null:
		return null
	return ContentRegistryHub.load_by_id(&"shops", shop_id) as ShopResource


func allows_buying() -> bool:
	return trades != Trades.SELL_ONLY


func allows_selling() -> bool:
	return trades != Trades.BUY_ONLY


## { "price": int, "currency": int } for one item, or {} if not sold here.
func entry_for(item_id: int) -> Dictionary:
	for entry: ShopEntry in entries:
		if entry and entry.item and int(entry.item.get_meta(&"id", 0)) == item_id:
			return {"price": entry.price, "currency": entry.currency}
	return {}
