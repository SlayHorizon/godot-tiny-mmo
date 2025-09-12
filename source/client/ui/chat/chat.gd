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
	peek_feed_message_edit.text_submitted.connect(_on_message_edit_text_submitted.bind(peek_feed_message_edit))
	full_feed_message_edit.text_submitted.connect(_on_message_edit_text_submitted.bind(full_feed_message_edit))
	
	peek_feed.show()
	full_feed.hide()
	
	Events.message_received.connect(_on_message_received)


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


func _on_message_received(message: String, sender_name: String, channel: int):
	var color_name: String = "#33caff"
	if sender_name == "Server":
		color_name = "#b6200f"
	
	var message_to_display: String = "[color=%s]%s:[/color] %s" % [color_name, sender_name, message]
	peek_feed_text_display.append_text(message_to_display)
	peek_feed_text_display.newline()
	peek_feed_text_display.show()
	fade_out_timer.start()
	
	if full_feed.visible and current_channel == channel:
		full_feed_text_display.append_text(message_to_display)
		full_feed_text_display.newline()
	
	if channel_messages.has(channel):
		channel_messages[channel].append(message_to_display)
	else:
		channel_messages[channel] = PackedStringArray([message_to_display])


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
	
	if not new_text.is_empty():
		new_text = new_text.strip_edges(true, true)
		new_text = new_text.substr(0, 120)
		Events.message_submitted.emit(new_text, current_channel)

	if line_edit == peek_feed_message_edit:
		fade_out_timer.start()
