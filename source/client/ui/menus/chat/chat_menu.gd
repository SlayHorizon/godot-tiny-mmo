extends Control


#region State
const MAX_MESSAGE_LEN: int = 120
const PROFILE_NAME_FETCH_COOLDOWN_MS: int = 10_000

# Channel mapping (client UX)
const CHANNEL_WORLD: int = 0
const CHANNEL_TEAM: int = 1
const CHANNEL_GUILD: int = 2
const CHANNEL_SYSTEM: int = 3

var messages_by_conversation: Dictionary[String, PackedStringArray] = {}
var conversation_buttons: Dictionary[String, Button] = {}

# DM display helpers
var dm_name_by_player_id: Dictionary[int, String] = {}
var pending_name_fetch_at_ms: Dictionary[int, int] = {}

var current_channel: int = CHANNEL_WORLD
var current_conversation_id: String = "global_0"
var current_dm_other_id: int = 0

var unread_by_conversation: Dictionary[String, int] = {}

var mute_peek_all: bool = false
var mute_peek_dm: bool = false
var mute_peek_world: bool = false

var _public_label_world: String = "World"
var _public_label_team: String = "Team"
var _public_label_guild: String = "Guild"

var fade_out_tween: Tween
#endregion


#region Nodes
@onready var peek_feed: VBoxContainer = $PeekFeed
@onready var full_feed: Control = $FullFeed

@onready var peek_feed_text_display: RichTextLabel = $PeekFeed/MessageDisplay
@onready var full_feed_text_display: RichTextLabel = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/RichTextLabel

@onready var peek_feed_message_edit: LineEdit = $PeekFeed/MessageEdit
@onready var full_feed_message_edit: LineEdit = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer2/LineEdit

@onready var fade_out_timer: Timer = $PeekFeed/FadeOutTimer

@onready var dm_container: VBoxContainer = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/ScrollContainer/VBoxContainer

@onready var world_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/WorldChatButton
@onready var team_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/TeamChatButton
@onready var guild_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/GuildChatButton
#endregion


func _ready() -> void:
	ClientState.dm_requested.connect(open_dm)

	Client.request_data(&"chat.history")
	Client.subscribe(&"chat.message", _on_chat_message)

	peek_feed_message_edit.text_submitted.connect(_on_message_edit_text_submitted.bind(peek_feed_message_edit))
	full_feed_message_edit.text_submitted.connect(_on_message_edit_text_submitted.bind(full_feed_message_edit))


	_public_label_world = world_chat_button.text
	_public_label_team = team_chat_button.text
	_public_label_guild = guild_chat_button.text

	_update_public_button_labels()

	world_chat_button.pressed.connect(_on_world_pressed)
	team_chat_button.pressed.connect(_on_team_pressed)
	guild_chat_button.pressed.connect(_on_guild_pressed)

	peek_feed.show()
	full_feed.hide()

	_ensure_conversation_exists(current_conversation_id)
	_refresh_full_feed()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"chat"):
		if not full_feed.visible and not peek_feed_message_edit.has_focus():
			get_viewport().set_input_as_handled()
			accept_event()
			open_chat()


func open_chat() -> void:
	peek_feed.show()
	_reset_peek_view()
	peek_feed_message_edit.grab_focus()
	fade_out_timer.stop()


#region Incoming messages
func _on_chat_message(message: Dictionary) -> void:
	if message.is_empty():
		return

	var text: String = str(message.get("text", ""))
	var sender_name: String = str(message.get("name", ""))
	var sender_id: int = int(message.get("id", 0))

	# Resolve conversation id (server may omit it for legacy channel payloads)
	var convo_id: String = str(message.get("conversation_id", ""))
	if convo_id.is_empty():
		var channel: int = int(message.get("channel", CHANNEL_WORLD))
		convo_id = _channel_conversation_id(channel)

	_ensure_conversation_exists(convo_id)

	# If DM: ensure button + try to resolve a stable name for the thread.
	if convo_id.begins_with("dm:"):
		var self_id: int = int(ClientState.player_id)
		var other_id: int = _dm_other_id_from_conversation(convo_id, self_id)
		if other_id > 0:
			# If we received a msg from the other, we learn their name instantly.
			if sender_id == other_id and not sender_name.is_empty():
				dm_name_by_player_id[other_id] = sender_name

			_ensure_dm_button(convo_id, other_id)

	var tag: String = _tag_for_conversation(convo_id)
	var text_to_display: String = _format_message(sender_id, sender_name, text, tag)

	# Store
	messages_by_conversation[convo_id].append(text_to_display)

	# Unread: count only if it's not from me and I'm not currently viewing this convo
	var self_player_id: int = int(ClientState.player_id)
	var is_self: bool = sender_id == self_player_id
	var is_currently_viewing: bool = full_feed.visible and current_conversation_id == convo_id
	if not is_self and not is_currently_viewing:
		_inc_unread(convo_id)

	# Peek feed: respect mutes
	if _should_show_in_peek(convo_id):
		peek_feed_text_display.append_text(text_to_display)
		peek_feed_text_display.newline()

	# Full feed: only append if we're currently reading this conversation
	if is_currently_viewing:
		full_feed_text_display.append_text(text_to_display)
		full_feed_text_display.newline()
	else:
		# Only fade when the full chat is closed
		if not full_feed.visible:
			_reset_peek_view()
			peek_feed_text_display.show()
			fade_out_timer.start()
#endregion


#region UI / Peek fade
func _on_fade_out_timer_timeout() -> void:
	if peek_feed_message_edit.has_focus():
		fade_out_timer.start()
		return

	if fade_out_tween != null:
		fade_out_tween.kill()

	fade_out_tween = create_tween()
	fade_out_tween.tween_property(peek_feed, ^"modulate:a", 0.0, 0.3)


func _on_peek_feed_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and peek_feed.modulate.a < 1.0:
		_reset_peek_view()
		fade_out_timer.start()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		peek_feed.hide()
		full_feed.show()
		_refresh_full_feed()


func _on_close_button_pressed() -> void:
	peek_feed.show()
	_reset_peek_view()
	full_feed.hide()


func _reset_peek_view() -> void:
	if fade_out_tween != null and fade_out_tween.is_running():
		fade_out_tween.kill()

	peek_feed.modulate.a = 1.0
#endregion


func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	ClientState.player_profile_requested.emit(str(meta).to_int())


#region Sending messages
func _on_message_edit_text_submitted(new_text: String, line_edit: LineEdit) -> void:
	line_edit.clear()
	line_edit.release_focus()

	if line_edit == peek_feed_message_edit:
		fade_out_timer.start()

	new_text = new_text.strip_edges(true, true)
	if new_text.is_empty():
		return

	new_text = new_text.substr(0, MAX_MESSAGE_LEN)

	# Commands
	if new_text.begins_with("/"):
		var cmd_line: String = new_text.substr(1)
		var split: PackedStringArray = cmd_line.split(" ", false, 5)
		var cmd: String = split[0]
		
		if cmd == "mute":
			_handle_local_mute_command(split)
			return
		
		Client.request_data(
			&"chat.command.exec",
			Callable(),
			{"cmd": cmd, "params": split},
			InstanceClient.current.name
		)
		return

	# Normal send (channel or dm)
	var payload: Dictionary = {"text": new_text}

	if current_conversation_id.begins_with("dm:"):
		payload["dm_target_id"] = current_dm_other_id
	else:
		payload["channel"] = current_channel

	Client.request_data(
		&"chat.message.send",
		Callable(),
		payload,
		InstanceClient.current.name
	)
#endregion


#region Public buttons
func _on_world_pressed() -> void:
	open_channel(CHANNEL_WORLD)


func _on_team_pressed() -> void:
	open_channel(CHANNEL_TEAM)


func _on_guild_pressed() -> void:
	open_channel(CHANNEL_GUILD)
#endregion


#region Conversations
func open_channel(channel: int) -> void:
	current_dm_other_id = 0
	current_channel = channel
	current_conversation_id = _channel_conversation_id(channel)

	_clear_unread(current_conversation_id)

	full_feed.show()
	peek_feed.hide()

	_ensure_conversation_exists(current_conversation_id)
	_refresh_full_feed()



func open_conversation(conversation_id: String) -> void:
	current_conversation_id = conversation_id
	_clear_unread(current_conversation_id)

	# If we open a DM conversation, keep "other id" synced for sending.
	if conversation_id.begins_with("dm:"):
		current_dm_other_id = _dm_other_id_from_conversation(conversation_id, int(ClientState.player_id))
	else:
		current_dm_other_id = 0
		if conversation_id.begins_with("global_"):
			current_channel = int(conversation_id.replace("global_", ""))

	full_feed.show()
	peek_feed.hide()

	_refresh_full_feed()


func open_dm(other_id: int) -> void:
	current_dm_other_id = other_id

	var self_id: int = int(ClientState.player_id)
	current_conversation_id = _dm_conversation_id(self_id, other_id)
	_clear_unread(current_conversation_id)

	_ensure_conversation_exists(current_conversation_id)
	_ensure_dm_button(current_conversation_id, other_id)

	full_feed.show()
	peek_feed.hide()
	_refresh_full_feed()

	_request_player_name_if_needed(other_id)

	Client.request_data(
		&"chat.dm.history",
		Callable(), # history is pushed as chat.message events
		{"other_id": other_id, "limit": 50},
		InstanceClient.current.name
	)


func _refresh_full_feed() -> void:
	full_feed_text_display.clear()
	full_feed_text_display.text = ""

	var arr: PackedStringArray = messages_by_conversation.get(current_conversation_id, PackedStringArray())
	for line: String in arr:
		full_feed_text_display.append_text(line)
		full_feed_text_display.newline()
#endregion


#region Helpers
func _channel_conversation_id(channel: int) -> String:
	return "global_%d" % channel


func _dm_conversation_id(a: int, b: int) -> String:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	return "dm:%d:%d" % [lo, hi]


func _dm_other_id_from_conversation(convo_id: String, self_id: int) -> int:
	# convo_id format: "dm:<lo>:<hi>"
	var parts: PackedStringArray = convo_id.split(":", false)
	if parts.size() != 3:
		return 0

	var lo: int = int(parts[1])
	var hi: int = int(parts[2])

	if self_id == lo:
		return hi
	if self_id == hi:
		return lo

	return 0


func _ensure_conversation_exists(convo_id: String) -> void:
	if not messages_by_conversation.has(convo_id):
		messages_by_conversation[convo_id] = PackedStringArray()


func _ensure_dm_button(convo_id: String, other_id: int) -> void:
	if conversation_buttons.has(convo_id):
		_update_dm_button_label(convo_id, other_id)
		return

	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(open_conversation.bind(convo_id))

	dm_container.add_child(button)
	conversation_buttons[convo_id] = button

	_update_dm_button_label(convo_id, other_id)
	_request_player_name_if_needed(other_id)


func _update_dm_button_label(convo_id: String, other_id: int) -> void:
	var button: Button = conversation_buttons.get(convo_id)
	if button == null:
		return

	var _name: String = str(dm_name_by_player_id.get(other_id, ""))
	if _name.is_empty():
		_name = "DM %d" % other_id

	var unread: int = _get_unread(convo_id)
	button.text = ("(%d) %s" % [unread, _name]) if unread > 0 else _name



func _request_player_name_if_needed(player_id: int) -> void:
	if player_id <= 0:
		return

	if dm_name_by_player_id.has(player_id) and not str(dm_name_by_player_id[player_id]).is_empty():
		return

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var last_ms: int = int(pending_name_fetch_at_ms.get(player_id, 0))
	if now_ms - last_ms < PROFILE_NAME_FETCH_COOLDOWN_MS:
		return

	pending_name_fetch_at_ms[player_id] = now_ms

	Client.request_data(
		&"profile.get",
		_on_profile_received.bind(player_id),
		{"id": player_id},
		InstanceClient.current.name
	)


func _on_profile_received(profile: Dictionary, player_id: int) -> void:
	var player_name: String = str(profile.get("name", ""))
	if player_name.is_empty():
		return

	dm_name_by_player_id[player_id] = player_name

	# Update any existing DM button that targets this player.
	var self_id: int = int(ClientState.player_id)
	var convo_id: String = _dm_conversation_id(self_id, player_id)
	_update_dm_button_label(convo_id, player_id)


func _tag_for_conversation(convo_id: String) -> String:
	if convo_id.begins_with("dm:"):
		return "[DM]"

	if convo_id.begins_with("global_"):
		var channel: int = int(convo_id.replace("global_", ""))
		if channel == CHANNEL_WORLD:
			return "[World]"
		if channel == CHANNEL_TEAM:
			return "[Team]"
		if channel == CHANNEL_GUILD:
			return "[Guild]"
		if channel == CHANNEL_SYSTEM:
			return "[System]"
		return "[Global]"

	return "[Chat]"


func _format_message(sender_id: int, sender_name: String, text: String, tag: String) -> String:
	var color_name: String = "#33caff"
	var name_to_display: String = ""

	if sender_id == 1:
		color_name = "#b6200f"
		name_to_display = sender_name
	else:
		name_to_display = "[url=%d]%s[/url]" % [sender_id, sender_name]

	# Tag is plain text prefix for readability in peek feed.
	return "%s [color=%s]%s:[/color] %s" % [tag, color_name, name_to_display, text]


func _get_unread(convo_id: String) -> int:
	return int(unread_by_conversation.get(convo_id, 0))


func _set_unread(convo_id: String, v: int) -> void:
	unread_by_conversation[convo_id] = maxi(v, 0)

	# DM buttons
	_update_conversation_button_title(convo_id)

	# Public channel buttons (World/Team/Guild)
	_update_public_button_labels()


func _inc_unread(convo_id: String) -> void:
	_set_unread(convo_id, _get_unread(convo_id) + 1)


func _clear_unread(convo_id: String) -> void:
	_set_unread(convo_id, 0)


func _update_conversation_button_title(convo_id: String) -> void:
	if not convo_id.begins_with("dm:"):
		return # for now: only DM buttons live in dm_container

	var self_id: int = int(ClientState.player_id)
	var other_id: int = _dm_other_id_from_conversation(convo_id, self_id)
	if other_id > 0:
		_update_dm_button_label(convo_id, other_id)


func _should_show_in_peek(convo_id: String) -> bool:
	if mute_peek_all:
		return false
	if convo_id.begins_with("dm:"):
		return not mute_peek_dm
	if convo_id == "global_%d" % CHANNEL_WORLD:
		return not mute_peek_world
	return true


func _handle_local_mute_command(args: PackedStringArray) -> void:
	# /mute dm | world | all | off
	if args.size() < 2:
		_system_echo("Usage: /mute dm|world|all|off")
		return

	var what: String = args[1].to_lower()

	if what == "dm":
		mute_peek_dm = not mute_peek_dm
		_system_echo("Peek DM mute: %s" % ("ON" if mute_peek_dm else "OFF"))
	elif what == "world":
		mute_peek_world = not mute_peek_world
		_system_echo("Peek World mute: %s" % ("ON" if mute_peek_world else "OFF"))
	elif what == "all":
		mute_peek_all = not mute_peek_all
		_system_echo("Peek All mute: %s" % ("ON" if mute_peek_all else "OFF"))
	elif what == "off":
		mute_peek_all = false
		mute_peek_dm = false
		mute_peek_world = false
		_system_echo("Peek mutes cleared.")
	else:
		_system_echo("Unknown: %s" % what)


func _system_echo(text: String) -> void:
	var line: String = "[System] [color=#b6200f]system:[/color] %s" % text
	peek_feed_text_display.append_text(line)
	peek_feed_text_display.newline()


func _update_public_button_labels() -> void:
	_set_public_button_text(world_chat_button, _public_label_world, _channel_conversation_id(CHANNEL_WORLD))
	_set_public_button_text(team_chat_button, _public_label_team, _channel_conversation_id(CHANNEL_TEAM))
	_set_public_button_text(guild_chat_button, _public_label_guild, _channel_conversation_id(CHANNEL_GUILD))


func _set_public_button_text(button: Button, base_label: String, convo_id: String) -> void:
	if button == null:
		return

	var unread: int = _get_unread(convo_id)
	button.text = ("%s (%d)" % [base_label, unread]) if unread > 0 else base_label
#endregion
