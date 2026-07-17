class_name QuestItem
extends Item

@export var quest_id: int = 0
@export var auto_bind: bool = true


func _init() -> void:
	can_trade = false
	stack_limit = 1


func inventory_tab() -> InventoryTab:
	return InventoryTab.QUEST


func group_key() -> StringName:
	return &"quest"
