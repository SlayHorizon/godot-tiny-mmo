class_name LootDrop
extends Resource
## One possible drop from an enemy: an item, a quantity range, and a roll chance.

@export var item: Item
@export var min_amount: int = 1
@export var max_amount: int = 1
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
