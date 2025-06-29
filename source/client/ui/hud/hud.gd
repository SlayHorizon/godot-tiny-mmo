class_name HUD
extends CanvasLayer


func _ready() -> void:
	pass


func _on_item_slot_button_1_pressed(extra_arg_0: String) -> void:
	Events.item_icon_pressed.emit(extra_arg_0)


func _on_item_slot_button_2_pressed(extra_arg_0: String) -> void:
	Events.item_icon_pressed.emit(extra_arg_0)
