class_name QuestItem
extends Item

@export var quest_id: int = 0
@export var auto_bind: bool = true


func _init() -> void:
	can_trade = false
	can_sell = false
	stack_limit = 1
	#inventory_tab = Item.InventoryTab.OTHER
