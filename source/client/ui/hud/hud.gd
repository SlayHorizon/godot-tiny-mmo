extends CanvasLayer


func _on_item_slot_button_1_pressed(extra_arg_0: String) -> void:
	ClientEvents.item_icon_pressed.emit(extra_arg_0)


func _on_item_slot_button_2_pressed(extra_arg_0: String) -> void:
	ClientEvents.item_icon_pressed.emit(extra_arg_0)
