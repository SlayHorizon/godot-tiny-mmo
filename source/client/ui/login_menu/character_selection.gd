extends Control


@export var next_menu: Control


func _on_character_slot_button_pressed() -> void:
	hide()
	next_menu.show()
