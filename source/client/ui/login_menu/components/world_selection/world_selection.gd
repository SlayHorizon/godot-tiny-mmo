extends Control


const WORLD_BUTTON = preload("res://source/client/ui/login_menu/components/world_selection/world_button/world_button.tscn")

@export var character_selection_menu: Control

@onready var world_buttons: HBoxContainer = $CenterContainer/VBoxContainer/HBoxContainer
@onready var confirm_button: Button = $CenterContainer/VBoxContainer/ConfirmButton


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
	print("World ID pressed: %d" % world_id)
	GatewayClient.world_id = world_id
	confirm_button.disabled = false


func _on_confirm_button_pressed() -> void:
	confirm_button.disabled = true
	GatewayClient.gateway.request_player_characters.rpc_id(
		1,
		GatewayClient.world_id
	)
	GatewayClient.gateway.player_characters_received.connect(
		func(player_characters: Dictionary):
			if player_characters.has("error"):
				var label = $CenterContainer/VBoxContainer/Label
				label.text = player_characters["error"]
			else:
				character_selection_menu.set_player_characters(player_characters)
				hide()
				character_selection_menu.show()
			,
		CONNECT_ONE_SHOT
	)
