extends Control


func _ready() -> void:
	ClientEvents.message_received.connect(_on_message_received)


func _input(_event: InputEvent) -> void:
	if (
		Input.is_action_just_pressed("chat")
		and not %MessageEdit.has_focus()
	):
		accept_event()
		open_chat()


func open_chat() -> void:
	%MessageDisplay.show()
	%MessageEdit.show()
	%MessageEdit.grab_focus()
	%FadeOutTimer.stop()


func hide_chat() -> void:
	%MessageDisplay.hide()
	%MessageEdit.hide()


func _on_message_submitted(new_message: String) -> void:
	%MessageEdit.clear()
	%MessageEdit.release_focus()
	%MessageEdit.hide()
	if not new_message.is_empty():
		new_message = new_message.strip_edges(true, true)
		new_message = new_message.substr(0, 120)
		ClientEvents.message_submitted.emit(new_message)
	%FadeOutTimer.start()


func _on_message_received(message: String, sender_name: String):
	var color_name: String = "#33caff"
	if sender_name == "Server":
		color_name = "#b6200f"
	var message_to_display: String = "[color=%s]%s:[/color] %s" % [color_name, sender_name, message]
	%MessageDisplay.append_text(message_to_display)
	%MessageDisplay.newline()
	%MessageDisplay.show()
	%FadeOutTimer.start()


func _on_fade_out_timer_timeout() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0, 0.3)
	await tween.finished
	hide_chat()
	modulate.a = 1.0
