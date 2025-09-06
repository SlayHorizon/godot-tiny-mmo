class_name Item
extends Resource


# Definition
@export var item_name: StringName = &"ItemDefault"
@export var item_icon: CompressedTexture2D
@export_multiline var description: String

# Trading / Economy
## Can trade for goods between players.
@export var can_trade: bool = false
## Can sell to the consigment house.
@export var can_sell: bool = false
## Minimum price the item can be sold at consigment house.
## If 0 any price can be choosen.
## This is not shop price. If an item is sold at a shop, the price is defined in shop logic.
@export var minimum_price: int = 0


# Inventory
## If 0 no limit.
@export_range(0, 99, 1.0) var stack_limit: int = 0
## Optional free-form tags for filters/crafting
@export var tags: PackedStringArray = []


func is_stackable() -> bool:
	return stack_limit != 1


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
func on_equip(character: Character) -> void:
	pass


@warning_ignore("unused_parameter")
func on_unequip(character: Character) -> void:
	pass
