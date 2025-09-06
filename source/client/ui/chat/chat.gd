extends Control


var channel_messages: Dictionary[int, PackedStringArray]
var current_channel: int = 0


func _ready() -> void:
	Events.message_received.connect(_on_message_received)


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
		Events.message_submitted.emit(new_message, current_channel)
	%FadeOutTimer.start()


func _on_message_received(message: String, sender_name: String, channel: int):
	var color_name: String = "#33caff"
	if sender_name == "Server":
		color_name = "#b6200f"
	var message_to_display: String = "[color=%s]%s:[/color] %s" % [color_name, sender_name, message]
	%MessageDisplay.append_text(message_to_display)
	%MessageDisplay.newline()
	%MessageDisplay.show()
	%FadeOutTimer.start()
	
	# NEW
	if channel_messages.has(channel):
		channel_messages[channel].append(message_to_display)
	else:
		channel_messages[channel] = PackedStringArray()


func _on_fade_out_timer_timeout() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0, 0.3)
	await tween.finished
	hide_chat()
	modulate.a = 1.0


func _on_peek_feed_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		$PeekFeed.hide()
