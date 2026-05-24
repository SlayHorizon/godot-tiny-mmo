class_name ShopEntry
extends Resource
## A single item for sale in a shop. Reference the item resource directly so shops
## can be designed in the editor; the registry id is read from the item's metadata.

## Reserved for future event / alternate currencies. Only GOLDS is implemented today.
enum Currency { GOLDS }

@export var item: Item
@export var price: int
@export var currency: Currency
