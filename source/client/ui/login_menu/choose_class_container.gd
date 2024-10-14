extends VBoxContainer


var player_class := "knight"


func _ready() -> void:
	for button: Button in $ClassButtonsContainer.get_children():
		button.pressed.connect(func():
			player_class = button.get_node("Label").text.to_lower()
		)
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
