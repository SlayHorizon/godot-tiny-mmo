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
## Default currency the whole shop trades in (e.g. event tokens for a fair
## stall). Leave empty for gold. A per-entry [member ShopEntry.currency_item]
## overrides this for that one item.
@export var currency_item: Item
@export var entries: Array[ShopEntry]
@export var trades: Trades = Trades.BOTH
## Specialty recurring exchanges this vendor offers (e.g. Mira always accepts
## 5 Healing Herbs for 4 gold). Empty for generic vendors.
@export var accepted_trades: Array[ShopTrade]


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


## True if this vendor offers any specialty trades. Specialty trades can be made
## even at a vendor that doesn't allow generic selling (e.g. an herbalist who
## accepts only herbs). Defensive against shops authored before the
## accepted_trades field existed (where it can deserialize as null).
func has_trades() -> bool:
	return accepted_trades != null and not accepted_trades.is_empty()


## { "price": int, "currency_id": int } for one item, or {} if not sold here.
## currency_id resolves entry → shop → gold (first non-null wins).
func entry_for(item_id: int) -> Dictionary:
	for entry: ShopEntry in entries:
		if entry and entry.item and int(entry.item.get_meta(&"id", 0)) == item_id:
			return {"price": entry.price, "currency_id": _resolve_currency_id(entry.currency_item)}
	return {}


## The currency id to charge for [param entry_currency]: the per-entry currency
## if set, else the shop's default currency, else gold.
func _resolve_currency_id(entry_currency: Item) -> int:
	if entry_currency != null:
		return int(entry_currency.get_meta(&"id", 0))
	if currency_item != null:
		return int(currency_item.get_meta(&"id", 0))
	return Economy.gold_id()


## The shop's display currency id (default for the UI's balance + price chips).
func display_currency_id() -> int:
	if currency_item != null:
		return int(currency_item.get_meta(&"id", 0))
	return Economy.gold_id()
