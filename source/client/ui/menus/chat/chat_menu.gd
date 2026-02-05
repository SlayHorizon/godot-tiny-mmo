extends Control


#region Constants
const MAX_MESSAGE_LEN: int = 120
const PROFILE_NAME_FETCH_COOLDOWN_MS: int = 10_000

const CHANNEL_WORLD: int = ChatConstants.CHANNEL_WORLD
const CHANNEL_TEAM: int = ChatConstants.CHANNEL_TEAM
const CHANNEL_GUILD: int = ChatConstants.CHANNEL_GUILD
const CHANNEL_SYSTEM: int = ChatConstants.CHANNEL_SYSTEM

const TAG_COLOR_DM: String = "#d56bff"
const TAG_COLOR_WORLD: String = "#66d9ff"
const TAG_COLOR_TEAM: String = "#7dff9a"
const TAG_COLOR_GUILD: String = "#ffd36b"
const TAG_COLOR_SYSTEM: String = "#ff6b6b"

const BOOTSTRAP_LIMIT: int = 50
const HISTORY_LIMIT: int = 50
#endregion


#region State
var messages_by_conversation: Dictionary[String, PackedStringArray] = {}
var conversation_buttons: Dictionary[String, Button] = {}

var dm_name_by_player_id: Dictionary[int, String] = {}
var pending_name_fetch_at_ms: Dictionary[int, int] = {}

var unread_by_conversation: Dictionary[String, int] = {}

var seen_msg_ids_by_conversation: Dictionary[String, Dictionary] = {}
var history_requested_by_conversation: Dictionary[String, bool] = {}

var current_channel: int = CHANNEL_WORLD
var current_conversation_id: String = ""
var current_dm_other_id: int = 0

var mute_peek_all: bool = false
var mute_peek_system: bool = false
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
@onready var peek_feed_message_edit: LineEdit = $PeekFeed/MessageEdit
@onready var fade_out_timer: Timer = $PeekFeed/FadeOutTimer

@onready var full_feed_text_display: RichTextLabel = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/RichTextLabel
@onready var full_feed_message_edit: LineEdit = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer2/LineEdit

@onready var dm_container: VBoxContainer = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/ScrollContainer/VBoxContainer

@onready var system_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/SystemChatButton
@onready var world_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/WorldChatButton
@onready var team_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/TeamChatButton
@onready var guild_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/GuildChatButton

@onready var chat_title_label: Label = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer/ChatTitleLabel
@onready var settings_button: Button = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer/SettingsButton
#endregion


func _ready() -> void:
	ClientState.dm_requested.connect(open_dm)

	Client.subscribe(&"chat.message", _on_chat_message)
	Client.request_data(&"chat.bootstrap", Callable(), {"limit": BOOTSTRAP_LIMIT}, InstanceClient.current.name)

	peek_feed_message_edit.text_submitted.connect(_on_text_submitted.bind(peek_feed_message_edit))
	full_feed_message_edit.text_submitted.connect(_on_text_submitted.bind(full_feed_message_edit))

	_public_label_world = world_chat_button.text
	_public_label_team = team_chat_button.text
	_public_label_guild = guild_chat_button.text

	world_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_WORLD))
	team_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_TEAM))
	guild_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_GUILD))
	system_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_SYSTEM))

	current_conversation_id = ChatConstants.channel_conversation_id(CHANNEL_WORLD)
	_ensure_conversation_exists(current_conversation_id)

	_sync_channel_buttons()
	_update_public_button_labels()

	peek_feed.show()
	full_feed.hide()

	_refresh_full_feed()
	_refresh_title_and_input()
	_update_input_enabled_state()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"chat"):
		if not full_feed.visible and not peek_feed_message_edit.has_focus():
			get_viewport().set_input_as_handled()
			accept_event()
			_open_peek_for_typing()


func _open_peek_for_typing() -> void:
	peek_feed.show()
	_reset_peek_view()
	peek_feed_message_edit.grab_focus()
	fade_out_timer.stop()


#region Incoming
func _on_chat_message(message: Dictionary) -> void:
	if message.is_empty():
		return

	var text: String = str(message.get("text", ""))
	var sender_name: String = str(message.get("name", ""))
	var sender_id: int = int(message.get("id", 0))
	var msg_id: int = int(message.get("msg_id", 0))
	var is_history: bool = bool(message.get("is_history", false))

	var convo_id: String = str(message.get("conversation_id", ""))
	if convo_id.is_empty():
		var channel: int = int(message.get("channel", CHANNEL_WORLD))
		convo_id = ChatConstants.channel_conversation_id(channel)

	_ensure_conversation_exists(convo_id)

	if msg_id > 0 and _is_duplicate_msg(convo_id, msg_id):
		return

	if convo_id.begins_with("dm:"):
		var self_id: int = int(ClientState.player_id)
		var other_id: int = _dm_other_id_from_conversation(convo_id, self_id)
		if other_id > 0:
			if sender_id == other_id and not sender_name.is_empty():
				dm_name_by_player_id[other_id] = sender_name
			_ensure_dm_button(convo_id, other_id)

	var full_line: String = _format_message_full(convo_id, sender_id, sender_name, text)
	messages_by_conversation[convo_id].append(full_line)

	var self_player_id: int = int(ClientState.player_id)
	var is_self: bool = sender_id == self_player_id
	var is_viewing: bool = full_feed.visible and current_conversation_id == convo_id

	if not is_history and not is_self and not is_viewing:
		_inc_unread(convo_id)

	if not is_history and _should_show_in_peek(convo_id):
		var peek_line: String = _format_message_peek(convo_id, sender_id, sender_name, text)
		peek_feed_text_display.append_text(peek_line)
		peek_feed_text_display.newline()

	if is_viewing:
		full_feed_text_display.append_text(full_line)
		full_feed_text_display.newline()
	else:
		if not is_history and not full_feed.visible:
			_reset_peek_view()
			peek_feed_text_display.show()
			fade_out_timer.start()

	_update_public_button_labels()
#endregion


#region Peek fade
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

		_sync_channel_buttons()
		_update_public_button_labels()

		_refresh_full_feed()
		_refresh_title_and_input()
		_update_input_enabled_state()


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


#region Sending
func _on_text_submitted(new_text: String, line_edit: LineEdit) -> void:
	line_edit.clear()
	line_edit.release_focus()

	var is_peek: bool = (line_edit == peek_feed_message_edit)
	if is_peek:
		fade_out_timer.start()

	new_text = new_text.strip_edges(true, true)
	if new_text.is_empty():
		return

	new_text = new_text.substr(0, MAX_MESSAGE_LEN)

	if new_text.begins_with("/"):
		_handle_command(new_text)
		return

	if is_peek:
		_send_channel_message(CHANNEL_WORLD, new_text)
		return

	if current_conversation_id.begins_with("dm:"):
		_send_dm_message(current_dm_other_id, new_text)
		return

	if _is_system_conversation(current_conversation_id):
		return

	if current_conversation_id.begins_with("guild:") and _get_active_guild_id() <= 0:
		_show_full_notice("You are not in a guild.")
		return

	if current_channel == CHANNEL_TEAM:
		_show_full_notice("Team chat not implemented yet.")
		return

	_send_channel_message(current_channel, new_text)


func _handle_command(raw: String) -> void:
	var cmd_line: String = raw.substr(1)
	var split: PackedStringArray = cmd_line.split(" ", false, 5)
	if split.is_empty():
		return

	var cmd: String = split[0].to_lower()

	if cmd == "mute":
		_handle_local_mute_command(split)
		return

	if cmd == "g":
		var guild_id: int = _get_active_guild_id()
		if guild_id <= 0:
			_system_echo("You are not in a guild.")
			return

		var msg: String = cmd_line.substr(2).strip_edges(true, true)
		if not msg.is_empty():
			_send_channel_message(CHANNEL_GUILD, msg)
		return

	if cmd == "t":
		_system_echo("Team chat not implemented yet.")
		return

	Client.request_data(
		&"chat.command.exec",
		Callable(),
		{"cmd": cmd, "params": split},
		InstanceClient.current.name
	)
#endregion


#region Navigation
func open_channel(channel: int) -> void:
	current_dm_other_id = 0
	current_channel = channel

	if channel == CHANNEL_WORLD:
		current_conversation_id = ChatConstants.channel_conversation_id(CHANNEL_WORLD)

	elif channel == CHANNEL_TEAM:
		current_conversation_id = ChatConstants.channel_conversation_id(CHANNEL_TEAM)

	elif channel == CHANNEL_GUILD:
		var guild_id: int = _get_active_guild_id()
		if guild_id <= 0:
			_show_full_notice("You are not in a guild.")
			return

		current_conversation_id = ChatConstants.guild_conversation_id(guild_id)
		_request_history_once(current_conversation_id, &"chat.guild.history", {"limit": HISTORY_LIMIT})

	elif channel == CHANNEL_SYSTEM:
		current_conversation_id = ChatConstants.system_conversation_id(ClientState.player_id)

	else:
		current_conversation_id = ChatConstants.channel_conversation_id(CHANNEL_WORLD)

	_clear_unread(current_conversation_id)

	full_feed.show()
	peek_feed.hide()

	_ensure_conversation_exists(current_conversation_id)

	_sync_channel_buttons()
	_update_public_button_labels()

	_refresh_full_feed()
	_refresh_title_and_input()
	_update_input_enabled_state()


func open_conversation(conversation_id: String) -> void:
	current_conversation_id = conversation_id
	_clear_unread(current_conversation_id)

	if conversation_id.begins_with("dm:"):
		current_dm_other_id = _dm_other_id_from_conversation(conversation_id, int(ClientState.player_id))
	else:
		current_dm_other_id = 0
		if conversation_id.begins_with("global_"):
			current_channel = int(conversation_id.replace("global_", ""))

	full_feed.show()
	peek_feed.hide()

	_sync_channel_buttons()
	_update_public_button_labels()

	_refresh_full_feed()
	_refresh_title_and_input()
	_update_input_enabled_state()


func open_dm(other_id: int) -> void:
	current_dm_other_id = other_id

	var self_id: int = int(ClientState.player_id)
	current_conversation_id = ChatConstants.dm_conversation_id(self_id, other_id)
	_clear_unread(current_conversation_id)

	_ensure_conversation_exists(current_conversation_id)
	_ensure_dm_button(current_conversation_id, other_id)

	full_feed.show()
	peek_feed.hide()

	_sync_channel_buttons()
	_update_public_button_labels()

	_refresh_full_feed()
	_refresh_title_and_input()
	_update_input_enabled_state()

	_request_player_name_if_needed(other_id)

	Client.request_data(
		&"chat.dm.history",
		Callable(),
		{"other_id": other_id, "limit": HISTORY_LIMIT},
		InstanceClient.current.name
	)
#endregion


#region Rendering
func _refresh_full_feed() -> void:
	full_feed_text_display.clear()
	full_feed_text_display.text = ""

	var arr: PackedStringArray = messages_by_conversation.get(current_conversation_id, PackedStringArray())
	for line: String in arr:
		full_feed_text_display.append_text(line)
		full_feed_text_display.newline()


func _refresh_title_and_input() -> void:
	if chat_title_label != null:
		chat_title_label.text = _title_for_current()


func _title_for_current() -> String:
	if current_conversation_id.begins_with("dm:"):
		var other_id: int = current_dm_other_id
		if other_id <= 0:
			other_id = _dm_other_id_from_conversation(current_conversation_id, int(ClientState.player_id))
		var name: String = str(dm_name_by_player_id.get(other_id, ""))
		return name if not name.is_empty() else "DM %d" % other_id

	if _is_system_conversation(current_conversation_id):
		return "System"

	if current_conversation_id.begins_with("guild:"):
		return _public_label_guild

	if current_conversation_id == ChatConstants.channel_conversation_id(CHANNEL_WORLD):
		return _public_label_world

	if current_conversation_id == ChatConstants.channel_conversation_id(CHANNEL_TEAM):
		return _public_label_team

	return "Chat"


func _show_full_notice(text: String) -> void:
	if not full_feed.visible:
		_system_echo(text)
		return

	full_feed_text_display.append_text("[color=%s][SYS][/color] %s" % [TAG_COLOR_SYSTEM, text])
	full_feed_text_display.newline()
#endregion


#region Formatting
func _format_message_full(convo_id: String, sender_id: int, sender_name: String, text: String) -> String:
	var color_name: String = "#33caff"
	var name_to_display: String = ""

	if sender_id == ChatConstants.SYSTEM_SENDER_ID:
		color_name = "#b6200f"
		name_to_display = sender_name
	else:
		name_to_display = "[url=%d]%s[/url]" % [sender_id, sender_name]

	var line: String = "[color=%s]%s:[/color] %s" % [color_name, name_to_display, text]

	if sender_id == int(ClientState.player_id):
		return "[right]%s[/right]" % line

	return line


func _format_message_full_no_right(sender_id: int, sender_name: String, text: String) -> String:
	var color_name: String = "#33caff"
	var name_to_display: String = ""

	if sender_id == ChatConstants.SYSTEM_SENDER_ID:
		color_name = "#b6200f"
		name_to_display = sender_name
	else:
		name_to_display = "[url=%d]%s[/url]" % [sender_id, sender_name]

	return "[color=%s]%s:[/color] %s" % [color_name, name_to_display, text]


func _format_message_peek(convo_id: String, sender_id: int, sender_name: String, text: String) -> String:
	var base: String = _format_message_full_no_right(sender_id, sender_name, text)

	var prefix: String = _peek_prefix_for_conversation(convo_id)
	if prefix.is_empty():
		return base

	var c: String = _tag_color_for_conversation(convo_id)
	return "[color=%s][%s][/color] %s" % [c, prefix, base]


func _peek_prefix_for_conversation(convo_id: String) -> String:
	if convo_id == ChatConstants.channel_conversation_id(CHANNEL_WORLD):
		return ""
	if convo_id.begins_with("dm:"):
		return "DM"
	if convo_id.begins_with("guild:"):
		return "GUILD"
	if _is_system_conversation(convo_id):
		return "SYS"
	if convo_id == ChatConstants.channel_conversation_id(CHANNEL_TEAM):
		return "TEAM"
	return "CHAT"


func _tag_color_for_conversation(convo_id: String) -> String:
	if convo_id.begins_with("dm:"):
		return TAG_COLOR_DM
	if convo_id.begins_with("guild:"):
		return TAG_COLOR_GUILD
	if _is_system_conversation(convo_id):
		return TAG_COLOR_SYSTEM

	if convo_id.begins_with("global_"):
		var channel: int = int(convo_id.replace("global_", ""))
		if channel == CHANNEL_WORLD:
			return TAG_COLOR_WORLD
		if channel == CHANNEL_TEAM:
			return TAG_COLOR_TEAM
		if channel == CHANNEL_GUILD:
			return TAG_COLOR_GUILD
		if channel == CHANNEL_SYSTEM:
			return TAG_COLOR_SYSTEM

	return "#aaaaaa"
#endregion


#region DM helpers
func _dm_other_id_from_conversation(convo_id: String, self_id: int) -> int:
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

	if not seen_msg_ids_by_conversation.has(convo_id):
		seen_msg_ids_by_conversation[convo_id] = {}
#endregion


#region DM buttons / names
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

	var name: String = str(dm_name_by_player_id.get(other_id, ""))
	if name.is_empty():
		name = "DM %d" % other_id

	var unread: int = _get_unread(convo_id)
	button.text = ("(%d) %s" % [unread, name]) if unread > 0 else name


func _request_player_name_if_needed(player_id: int) -> void:
	if player_id <= 0:
		return

	var known: String = str(dm_name_by_player_id.get(player_id, ""))
	if not known.is_empty():
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

	var self_id: int = int(ClientState.player_id)
	var convo_id: String = ChatConstants.dm_conversation_id(self_id, player_id)
	_update_dm_button_label(convo_id, player_id)

	if current_conversation_id == convo_id:
		_refresh_title_and_input()
#endregion


#region Unread + public labels
func _get_unread(convo_id: String) -> int:
	return int(unread_by_conversation.get(convo_id, 0))


func _set_unread(convo_id: String, v: int) -> void:
	unread_by_conversation[convo_id] = maxi(v, 0)
	_update_dm_button_if_needed(convo_id)
	_update_public_button_labels()


func _inc_unread(convo_id: String) -> void:
	_set_unread(convo_id, _get_unread(convo_id) + 1)


func _clear_unread(convo_id: String) -> void:
	_set_unread(convo_id, 0)


func _update_dm_button_if_needed(convo_id: String) -> void:
	if not convo_id.begins_with("dm:"):
		return

	var self_id: int = int(ClientState.player_id)
	var other_id: int = _dm_other_id_from_conversation(convo_id, self_id)
	if other_id > 0:
		_update_dm_button_label(convo_id, other_id)


func _update_public_button_labels() -> void:
	var self_id: int = int(ClientState.player_id)

	_set_public_button_text(world_chat_button, _public_label_world, ChatConstants.channel_conversation_id(CHANNEL_WORLD))
	_set_public_button_text(team_chat_button, _public_label_team, ChatConstants.channel_conversation_id(CHANNEL_TEAM))

	var guild_id: int = _get_active_guild_id()
	if guild_id > 0:
		_set_public_button_text(guild_chat_button, _public_label_guild, ChatConstants.guild_conversation_id(guild_id))
	else:
		guild_chat_button.text = _public_label_guild

	_set_public_button_text(system_chat_button, "System", ChatConstants.system_conversation_id(self_id))


func _set_public_button_text(button: Button, base_label: String, convo_id: String) -> void:
	if button == null:
		return

	var unread: int = _get_unread(convo_id)
	button.text = ("%s (%d)" % [base_label, unread]) if unread > 0 else base_label
#endregion


#region Peek mutes + echo
func _should_show_in_peek(convo_id: String) -> bool:
	if mute_peek_all:
		return false

	if convo_id.begins_with("dm:"):
		return not mute_peek_dm

	if convo_id == ChatConstants.channel_conversation_id(CHANNEL_WORLD):
		return not mute_peek_world

	if _is_system_conversation(convo_id):
		return not mute_peek_system

	return true


func _handle_local_mute_command(args: PackedStringArray) -> void:
	if args.size() < 2:
		_system_echo("Usage: /mute dm|world|sys|all|off")
		return

	var what: String = args[1].to_lower()

	if what == "dm":
		mute_peek_dm = not mute_peek_dm
		_system_echo("Peek DM mute: %s" % ("ON" if mute_peek_dm else "OFF"))
	elif what == "sys" or what == "system":
		mute_peek_system = not mute_peek_system
		_system_echo("Peek System mute: %s" % ("ON" if mute_peek_system else "OFF"))
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
		mute_peek_system = false
		_system_echo("Peek mutes cleared.")
	else:
		_system_echo("Unknown: %s" % what)


func _system_echo(text: String) -> void:
	peek_feed_text_display.append_text("[color=%s][SYS][/color] %s" % [TAG_COLOR_SYSTEM, text])
	peek_feed_text_display.newline()
#endregion


#region Networking
func _send_channel_message(channel: int, text: String) -> void:
	Client.request_data(
		&"chat.message.send",
		Callable(),
		{"text": text, "channel": channel},
		InstanceClient.current.name
	)


func _send_dm_message(other_id: int, text: String) -> void:
	if other_id <= 0:
		_system_echo("No DM target selected.")
		return

	Client.request_data(
		&"chat.message.send",
		Callable(),
		{"text": text, "dm_target_id": other_id},
		InstanceClient.current.name
	)
#endregion


#region UI state
func _update_input_enabled_state() -> void:
	var writable: bool = true

	if _is_system_conversation(current_conversation_id):
		writable = false
	elif current_channel == CHANNEL_TEAM:
		writable = false
	elif current_conversation_id.begins_with("guild:") and _get_active_guild_id() <= 0:
		writable = false

	full_feed_message_edit.editable = writable
	full_feed_message_edit.placeholder_text = "Read-only" if not writable else "Enter a message"


func _sync_channel_buttons() -> void:
	var guild_id: int = _get_active_guild_id()
	guild_chat_button.disabled = guild_id <= 0
	team_chat_button.disabled = true
#endregion


#region History / dedup
func _request_history_once(convo_id: String, topic: StringName, args: Dictionary) -> void:
	var already: bool = bool(history_requested_by_conversation.get(convo_id, false))
	if already:
		return

	history_requested_by_conversation[convo_id] = true
	Client.request_data(topic, Callable(), args, InstanceClient.current.name)


func _is_duplicate_msg(convo_id: String, msg_id: int) -> bool:
	if msg_id <= 0:
		return false

	if not seen_msg_ids_by_conversation.has(convo_id):
		seen_msg_ids_by_conversation[convo_id] = {}

	var seen: Dictionary = seen_msg_ids_by_conversation[convo_id]
	if seen.has(msg_id):
		return true

	seen[msg_id] = true
	return false
#endregion


#region Misc
func _get_active_guild_id() -> int:
	return int(ClientState.active_guild_id)


func _is_system_conversation(convo_id: String) -> bool:
	return convo_id.begins_with("sys:")
#endregion
