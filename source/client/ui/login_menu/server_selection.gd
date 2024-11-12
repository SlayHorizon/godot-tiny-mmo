extends Control


const WORLD_BUTTON = preload("res://source/client/ui/login_menu/world_button/world_button.tscn")

var selected_server := "Witwitnds"

@onready var world_buttons: HBoxContainer = $CenterContainer/VBoxContainer/HBoxContainer


func update_worlds_info(worlds_info: Dictionary) -> void:
	for button: Button in world_buttons.get_children():
		button.queue_free()
	for world_id: int in worlds_info:
		var new_button = WORLD_BUTTON.instantiate()
		world_buttons.add_child(new_button)
		new_button.world_id = world_id
		new_button.apply_world_info(worlds_info[world_id]["info"])
		new_button.pressed.connect(on_world_button_pressed.bind(world_id))


func on_world_button_pressed(world_id: int) -> void:
	print("WORLD ID = ", world_id)
	get_parent().selected_world_id = world_id
