extends Button
class_name GearSlotButton


@export var gear_slot: ItemSlot

var _pixel_icon: TextureRect


func _ready() -> void:
	if not gear_slot:
		disabled = true
		return
	
	tooltip_text = gear_slot.display_name
	_pixel_icon = PixelIcon.mount(self, gear_slot.icon)
	if gear_slot.unlock_rule.kind == SlotUnlockRule.Kind.PLAYER_LEVEL:
		text = str(gear_slot.unlock_rule.level)


## Swaps the displayed icon (equipped item art, or the empty-slot placeholder) and keeps it crisp.
func set_item_icon(texture: Texture2D) -> void:
	PixelIcon.set_art(_pixel_icon, texture)
