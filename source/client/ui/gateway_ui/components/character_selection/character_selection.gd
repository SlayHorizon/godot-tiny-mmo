extends GatewayUIComponent


const CHARACTER_SLOT_BUTTON = preload("res://source/client/ui/gateway_ui/components/character_selection/character_slot_button.tscn")


@export var next_menu: Control

@onready var slots_container: HBoxContainer = $CenterContainer/HBoxContainer

@onready var waiting_rect: ColorRect = $CenterContainer/WaitingRect


func _ready() -> void:
	for placeholder in slots_container.get_children():
		placeholder.queue_free()


func set_player_characters(player_characters: Dictionary) -> void:
	var new_character_slot := CHARACTER_SLOT_BUTTON.instantiate()
	new_character_slot.pressed.connect(_on_character_slot_button_pressed.bind(new_character_slot.text))
	slots_container.add_child(new_character_slot)
	for character_id in player_characters:
		new_character_slot = CHARACTER_SLOT_BUTTON.instantiate()
		new_character_slot.text = "%s\nClass: %s\nLevel: %d" % [
			player_characters[character_id]["name"],
			player_characters[character_id]["class"],
			player_characters[character_id]["level"],
		]
		new_character_slot.pressed.connect(
			_on_character_slot_button_pressed.bind(
				new_character_slot.text,
				character_id
			)
		)
		slots_container.add_child(new_character_slot)


func _on_character_slot_button_pressed(text: String, character_id: int = 0) -> void:
	if text == "Empty character slot": 
		hide()
		next_menu.show()
	else:
		gateway.request_login.rpc_id(
			1,
			gateway.world_id,
			character_id,
		)
