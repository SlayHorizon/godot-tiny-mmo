extends Control


@export var closed_button: Button
@export var full_feed_text: RichTextLabel

var channel_messages: Dictionary[int, PackedStringArray]
var current_channel: int = 0
var fade_out_tween: Tween

@onready var peek_feed: VBoxContainer = $PeekFeed


func _ready() -> void:
	peek_feed.show()
	$FullFeed.hide()
	Events.message_received.connect(_on_message_received)


func _input(_event: InputEvent) -> void:
	if _event.is_action_pressed(&"chat"):
		if not $FullFeed.visible and not %MessageEdit.has_focus():
			get_viewport().set_input_as_handled()
			accept_event()
			open_chat()


func open_chat() -> void:
	peek_feed.show()
	reset_view()
	%MessageEdit.grab_focus()
	%FadeOutTimer.stop()


func _on_message_submitted(new_message: String) -> void:
	%MessageEdit.clear()
	%MessageEdit.release_focus()
	#%MessageEdit.hide()
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
	
	if $FullFeed.visible and current_channel == channel:
		full_feed_text.append_text(message_to_display)
		full_feed_text.newline()
	
	if channel_messages.has(channel):
		channel_messages[channel].append(message_to_display)
	else:
		channel_messages[channel] = PackedStringArray([message_to_display])


func _on_fade_out_timer_timeout() -> void:
	if %MessageEdit.has_focus():
		%FadeOutTimer.start()
		return
	
	if fade_out_tween:
		fade_out_tween.kill()
	
	fade_out_tween = create_tween()
	fade_out_tween.tween_property(peek_feed, ^"modulate:a", 0, 0.3)


func _on_peek_feed_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and peek_feed.modulate.a < 1.0:
		reset_view()
		%FadeOutTimer.start()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		peek_feed.hide()
		$FullFeed.show()
		full_feed_text.clear()
		full_feed_text.text = ""
		for message: String in channel_messages[0]:
			full_feed_text.append_text(message)
			full_feed_text.newline()


func _on_close_button_pressed() -> void:
	peek_feed.show()
	reset_view()
	$FullFeed.hide()


func reset_view() -> void:
	if fade_out_tween and fade_out_tween.is_running():
		fade_out_tween.kill()
	peek_feed.modulate.a = 1.0


func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	$"..".open_player_profile(str(meta).to_int())


func _on_line_edit_text_submitted(new_text: String) -> void:
	var line_edit: LineEdit = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer2/LineEdit
	
	line_edit.clear()
	line_edit.release_focus()
	if not new_text.is_empty():
		new_text = new_text.strip_edges(true, true)
		new_text = new_text.substr(0, 120)
		Events.message_submitted.emit(new_text, current_channel)
