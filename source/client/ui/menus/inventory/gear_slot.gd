extends Button
class_name GearSlotButton


@export var gear_slot: ItemSlot


func _ready() -> void:
	if not gear_slot:
		disabled = true
		return
	
	tooltip_text = gear_slot.display_name
	icon = gear_slot.icon
	if gear_slot.unlock_rule.kind == SlotUnlockRule.Kind.PLAYER_LEVEL:
		text = str(gear_slot.unlock_rule.level)
