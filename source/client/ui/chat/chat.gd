extends Control


var channel_messages: Dictionary[int, PackedStringArray]
var current_channel: int
var fade_out_tween: Tween

@onready var peek_feed: VBoxContainer = $PeekFeed
@onready var full_feed: Control = $FullFeed

@onready var peek_feed_text_display: RichTextLabel = $PeekFeed/MessageDisplay
@onready var full_feed_text_display: RichTextLabel = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/RichTextLabel

@onready var peek_feed_message_edit: LineEdit = $PeekFeed/MessageEdit
@onready var full_feed_message_edit: LineEdit = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer2/LineEdit

@onready var fade_out_timer: Timer = $PeekFeed/FadeOutTimer


func _ready() -> void:
	InstanceClient.current.subscribe(&"chat.message", _on_chat_message)
	
	peek_feed_message_edit.text_submitted.connect(_on_message_edit_text_submitted.bind(peek_feed_message_edit))
	full_feed_message_edit.text_submitted.connect(_on_message_edit_text_submitted.bind(full_feed_message_edit))
	
	peek_feed.show()
	full_feed.hide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"chat"):
		if not full_feed.visible and not peek_feed_message_edit.has_focus():
			get_viewport().set_input_as_handled()
			accept_event()
			open_chat()


func open_chat() -> void:
	peek_feed.show()
	reset_view()
	peek_feed_message_edit.grab_focus()
	fade_out_timer.stop()


func _on_chat_message(message: Dictionary) -> void:
	if not message:
		return
	var text: String = message.get("text", "")
	var sender_name: String = message.get("name", "")
	var channel: int = message.get("channel", 0)
	var sender_id: int = message.get("id", 0)
	var color_name: String = "#33caff"
	var name_to_display: String
	if sender_id == 1:
		color_name = "#b6200f"
		name_to_display = sender_name
	else:
		name_to_display = "[url=%d]%s[/url]" % [sender_id, sender_name]
	var text_to_display: String = "[color=%s]%s:[/color] %s" % [color_name, name_to_display, text]
	
	peek_feed_text_display.append_text(text_to_display)
	peek_feed_text_display.newline()
	
	if full_feed.visible:
		if current_channel == channel:
			full_feed_text_display.append_text(text_to_display)
			full_feed_text_display.newline()
	else:
		peek_feed_text_display.show()
		fade_out_timer.start()
	if channel_messages.has(channel):
		channel_messages[channel].append(text_to_display)
	else:
		channel_messages[channel] = PackedStringArray([text_to_display])


func _on_fade_out_timer_timeout() -> void:
	if peek_feed_message_edit.has_focus():
		fade_out_timer.start()
		return
	
	if fade_out_tween:
		fade_out_tween.kill()
	
	fade_out_tween = create_tween()
	fade_out_tween.tween_property(peek_feed, ^"modulate:a", 0, 0.3)


func _on_peek_feed_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and peek_feed.modulate.a < 1.0:
		reset_view()
		fade_out_timer.start()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		peek_feed.hide()
		full_feed.show()
		full_feed_text_display.clear()
		full_feed_text_display.text = ""
		for message: String in channel_messages[0]:
			full_feed_text_display.append_text(message)
			full_feed_text_display.newline()


func _on_close_button_pressed() -> void:
	peek_feed.show()
	reset_view()
	full_feed.hide()


func reset_view() -> void:
	if fade_out_tween and fade_out_tween.is_running():
		fade_out_tween.kill()
	peek_feed.modulate.a = 1.0


func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	$"..".open_player_profile(str(meta).to_int())


func _on_message_edit_text_submitted(new_text: String, line_edit: LineEdit) -> void:
	line_edit.clear()
	line_edit.release_focus()
	
	if line_edit == peek_feed_message_edit:
		fade_out_timer.start()
	
	if new_text.is_empty():
		return
	
	new_text = new_text.strip_edges(true, true)
	new_text = new_text.substr(0, 120)
	
	if new_text.begins_with("/"):
		new_text = new_text.substr(1)
		var split: PackedStringArray = new_text.split(" ", false, 5)
		var cmd: String = split[0]
		var params: PackedStringArray = split
		
		InstanceClient.current.request_data(
			&"chat.command.exec",
			print_debug,
			{"cmd": cmd, "params": params}
		)
	else:
		InstanceClient.current.request_data(
			&"chat.message.send",
			Callable(), # ACK later
			{"text": new_text, "channel": current_channel}
		)
