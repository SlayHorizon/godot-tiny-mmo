class_name ShopEntry
extends Resource
## A single item for sale in a shop. Reference the item resource directly so shops
## can be designed in the editor; the registry id is read from the item's metadata.

## What the player gets.
@export var item: Item
## How much of the currency it costs.
@export var price: int
## What the player pays in (any currency item). Leave empty for the default (gold).
@export var currency_item: Item
