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


## Human-readable stat lines for tooltips, auto-generated from the item's REAL data
## (never from the hand-written description), so changing a stat never needs a copy
## edit. Base items (materials, currency) have none. Subclasses override. Mirrors
## QuestObjective.describe().
## Each entry is {"text": String} plus a semantic tag the tooltip colours by:
## either "stat": <Stat key> (a modifier) or "kind": &"weapon"/"level"/"heal"/
## "mana"/"charges". The data layer stays presentation-free; colours live in the UI.
func stat_lines() -> Array[Dictionary]:
	return []


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
