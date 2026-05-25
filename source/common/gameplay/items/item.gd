class_name Item
extends Resource


# Definition
@export var item_name: StringName = &"ItemDefault"
@export var item_icon: Texture2D = preload("res://assets/sprites/items/icons/Icon271.png")
@export_multiline var description: String

# Trading / Economy
## Marks this item as a currency (gold, event tokens, ...). Currency items are paid
## with / received in transactions, shown in the wallet, and hidden from the bag grid.
@export var is_currency: bool = false
## Can trade for goods between players.
@export var can_trade: bool = false
## Can sell to the consigment house.
@export var can_sell: bool = false
## Minimum price the item can be sold at consigment house.
## If 0 any price can be choosen.
## This is not shop price. If an item is sold at a shop, the price is defined in shop logic.
@export var market_minimum_price: int = 0
## Price an NPC vendor pays for this item when the player sells it.
## 0 = NPC vendors won't buy it (quest/bound/junk-safe default).
## Distinct from the consignment house fields above (player-to-player market).
@export var vendor_value: int


# Inventory
## If 0 no limit.
## 0 = pseudo infinite stack size
## 1 = non-stackable
@export_range(0, 99, 1.0) var stack_limit: int = 0
## Optional free-form tags for filters/crafting
@export var tags: PackedStringArray = []


func is_stackable() -> bool:
	return stack_limit == 0 or stack_limit > 1


@warning_ignore("unused_parameter")
func can_use(player: Player) -> bool:
	return false


@warning_ignore("unused_parameter")
func on_use(character: Character) -> void:
	pass


## If NPC needs to handle an equipment, we don't use this check, we directly equip it.
@warning_ignore("unused_parameter")
func can_equip(player: Player) -> bool:
	return false


@warning_ignore("unused_parameter")
func equip(character: Character) -> void:
	pass


@warning_ignore("unused_parameter")
func unequip(character: Character) -> void:
	pass
