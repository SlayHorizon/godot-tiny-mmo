extends GatewayUIComponent


const WORLD_BUTTON: PackedScene = preload("res://source/client/gateway/ui/components/world_selection/world_button/world_button.tscn")
const WorldButton: GDScript = preload("res://source/client/gateway/ui/components/world_selection/world_button/world_button.gd")

@export var character_selection_menu: Control

@onready var world_buttons: HBoxContainer = $CenterContainer/VBoxContainer/HBoxContainer
@onready var confirm_button: Button = $CenterContainer/VBoxContainer/ConfirmButton


func update_worlds_info(worlds_info: Dictionary) -> void:
	for button: Button in world_buttons.get_children():
		button.queue_free()
	for world_id: int in worlds_info:
		var new_button: WorldButton = WORLD_BUTTON.instantiate()
		world_buttons.add_child(new_button)
		new_button.world_id = world_id
		new_button.apply_world_info(worlds_info[world_id]["info"])
		new_button.pressed.connect(_on_world_button_pressed.bind(new_button))


func _on_world_button_pressed(world_button: WorldButton) -> void:
	if world_button.world_id == gateway.world_id and world_button.has_focus():
		_on_confirm_button_pressed()
		return
	print("World ID pressed: %d" % world_button.world_id)
	gateway.world_id = world_button.world_id
	confirm_button.disabled = false


func _on_confirm_button_pressed() -> void:
	confirm_button.disabled = true
	gateway.request_player_characters.rpc_id(
		1,
		gateway.world_id
	)
	gateway.player_characters_received.connect(
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
