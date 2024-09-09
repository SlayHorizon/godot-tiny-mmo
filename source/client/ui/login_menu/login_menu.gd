class_name LoginMenu
extends Control

signal connection_succeed

var player_class: String = "knight"

@export var container : HBoxContainer

func _ready() -> void:
	Client.connection_changed.connect(self._on_connection_changed)
	for button: Button in container.get_children():
		button.pivot_offset = button.size / 2
		button.mouse_entered.connect(func():
			var tween := create_tween()
			tween.tween_property(button, "scale", Vector2(1.2, 1.2), 0.2) \
				.from(Vector2.ONE)
			button.get_node("CenterContainer/Control/AnimatedSprite2D").play("run")
		)
		button.mouse_exited.connect(func():
			var tween := create_tween()
			tween.tween_property(button, "scale", Vector2.ONE, 0.2) \
				.from_current()
			if not button.has_focus():
				button.get_node("CenterContainer/Control/AnimatedSprite2D").play("idle")
		)
		button.pressed.connect(func():
			player_class = (button.get_node("Label") as Label).text.to_lower()
		)


func _on_connection_changed(connection_status: bool) -> void:
	if connection_status:
		%ServerStatusLabel.text = "Connected to the server!"
		%LoginButton.disabled = true
		connection_succeed.emit()
	else:
		%ServerStatusLabel.text = "Authentication failed.\nEnter a correct name and choose a class."
		await get_tree().create_timer(1.2).timeout
		%LoginButton.disabled = false

func _on_login_button_pressed() -> void:
	%LoginButton.disabled = true
	Client.authentication_data = {
		"username": %EnterNameInput.text,
		"class": player_class
	}
	Client.connect_to_server()
