extends GatewayUIComponent



@export var class_description: Label

var selected_character_class: CharacterResource = preload("res://source/common/resources/custom/character/character_collection/knight.tres")

@onready var class_selection_container: VBoxContainer = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer
@onready var character_preview: AnimatedSprite2D = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer2/CenterContainer/Control/AnimatedSprite2D
@onready var username_edit: LineEdit = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer2/HBoxContainer/LineEdit
@onready var create_character_button: Button = $CenterContainer/VBoxContainer/CreateCharacterButton

@onready var result_message_label: Label = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer2/ResultMessageLabel


func _ready() -> void:
	create_character_button.disabled = true
	
	character_preview.sprite_frames = selected_character_class.character_sprite
	update_character_class_description()
	character_preview.play(&"idle")
	
	connect_class_buttons()


func generate_random_username() -> String:
	var characters := "abcdefghijklmnopqrstuvwxyz0123456789"
	var username := ""
	for i in range(8):
		username += characters[randi()% len(characters)]
	return username


func connect_class_buttons() -> void:
	for child in class_selection_container.get_children():
		if child is CharacterClassButton:
			child.pivot_offset = child.size / 2
			child.pressed.connect(_on_character_class_button_pressed.bind(child.character_class))
			child.mouse_entered.connect(
				func():
					var tween := create_tween()
					tween.tween_property(child, "scale", Vector2(1.2, 1.2), 0.2) \
						.from(Vector2.ONE)
					child.get_node("CenterContainer/Control/AnimatedSprite2D").play("run")
			)
			child.mouse_exited.connect(
				func():
					var tween := create_tween()
					tween.tween_property(child, "scale", Vector2.ONE, 0.2) \
						.from_current()
					if not child.has_focus():
						child.get_node("CenterContainer/Control/AnimatedSprite2D").play("idle")
			)
			child.focus_exited.connect(
				func():
					child.get_node("CenterContainer/Control/AnimatedSprite2D").play("idle")
			)


func _on_character_class_button_pressed(character_class: CharacterResource) -> void:
	selected_character_class = character_class
	update_character_class_description()
	character_preview.sprite_frames = character_class.character_sprite
	character_preview.play(&"idle") 

func _on_rng_button_pressed() -> void:
	username_edit.text = generate_random_username()
	create_character_button.disabled = false


func _on_line_edit_text_changed(new_text: String) -> void:
	if (
		new_text.length() > 4
		and new_text.length() < 13
		#Banword check? (should be on server anyway)
		and not new_text.contains("guest")
	):
		create_character_button.disabled = false
	else:
		create_character_button.disabled = true


func _on_create_character_button_pressed() -> void:
	create_character_button.disabled = true
	gateway.player_character_creation_result_received.connect(
		func(result_code: int):
			var message := "Creation successful."
			if result_code < 0:
				message = GatewayClient.get_error_message(abs(result_code))
			result_message_label.text = message
			await get_tree().create_timer(0.5).timeout
			if result_code != OK:
				create_character_button.disabled = false,
		ConnectFlags.CONNECT_ONE_SHOT
	)
	gateway.create_player_character_request.rpc_id(
		1,
		{
			"name": username_edit.text,
			"class": selected_character_class.character_name.to_lower()
		},
		gateway.world_id
	)


func update_character_class_description() -> void:
	class_description.text = "%s\n%s" % [
		selected_character_class.character_name,
		selected_character_class.description
	]
