extends Control


#region Constants
const MAX_MESSAGE_LEN: int = 120
const PROFILE_NAME_FETCH_COOLDOWN_MS: int = 10_000

const CHANNEL_WORLD: int = ChatConstants.CHANNEL_WORLD
const CHANNEL_TEAM: int = ChatConstants.CHANNEL_TEAM
const CHANNEL_GUILD: int = ChatConstants.CHANNEL_GUILD
const CHANNEL_SYSTEM: int = ChatConstants.CHANNEL_SYSTEM
## Synthetic channel — local-only aggregate view across every conversation.
const CHANNEL_ALL: int = -1
const ALL_CONVERSATION_ID: String = "all"

const TAG_COLOR_DM: String = "#d56bff"
const TAG_COLOR_WORLD: String = "#66d9ff"
const TAG_COLOR_TEAM: String = "#7dff9a"
const TAG_COLOR_GUILD: String = "#ffd36b"
const TAG_COLOR_SYSTEM: String = "#ff6b6b"
const TAG_COLOR_ALL: String = "#cccccc"

## Color used for our own name in two-line layout (kept neutral so the
## hash-coloured names of other people pop and our own messages read as
## "me" at a glance).
const SELF_NAME_COLOR: String = "#bdbdbd"
const SYSTEM_NAME_COLOR: String = "#ff6b6b"
## Subtle grey used for the (Guild) / « Title » suffixes and timestamps.
const SUBTLE_COLOR: String = "#7a7a7a"
const TITLE_COLOR: String = "#c8b977"

## If the previous message in the same conversation is from the same sender
## and within this window, suppress the duplicated name header (Discord-style).
const COLLAPSE_WINDOW_MS: int = 5 * 60 * 1000
## Insert a centered grey timestamp divider when more than this much time has
## passed since the previous message in the conversation.
const TIMESTAMP_DIVIDER_GAP_MS: int = 10 * 60 * 1000

const BOOTSTRAP_LIMIT: int = 50
const HISTORY_LIMIT: int = 50

## How far the full-feed content slides in (px from the left) on open, matched to the menu overlay's
## slide so both panels animate consistently.
const FULL_FEED_SLIDE: float = 48.0

## HUD chat-toggle icons: the plain message glyph, swapped for the exclamation variant while an unread
## DM is waiting. Public/guild/system are ambient + shown in the peek, so they deliberately don't badge it.
const CHAT_ICON: Texture2D = preload("res://assets/sprites/ui/menu_icons_shadow/16px/message.png")
const CHAT_ICON_UNREAD: Texture2D = preload("res://assets/sprites/ui/menu_icons_shadow/16px/message_exclamation.png")
#endregion


#region State
## Raw per-conversation message log. Each entry is a Dictionary with the
## same shape as the chat.message push (id, name, title, guild_name, text,
## time_ms, channel) plus a few derived booleans. We re-format on render
## instead of caching strings so the same-sender collapse + timestamp
## dividers stay consistent even after history backfills.
var raw_messages_by_conversation: Dictionary[String, Array] = {}
var conversation_buttons: Dictionary[String, Button] = {}

var dm_name_by_player_id: Dictionary[int, String] = {}
var pending_name_fetch_at_ms: Dictionary[int, int] = {}

var unread_by_conversation: Dictionary[String, int] = {}

var seen_msg_ids_by_conversation: Dictionary[String, Dictionary] = {}
var history_requested_by_conversation: Dictionary[String, bool] = {}

var current_channel: int = CHANNEL_WORLD
var current_conversation_id: String = ""
var current_dm_other_id: int = 0

var mute_peek_system: bool = false
var mute_peek_dm: bool = false
var mute_peek_world: bool = false

## How long the peek feed stays fully visible before the fade animation
## starts. 0 = "never fade" (peek stays until dismissed). Persisted to
## ClientState.settings under chat / peek_fade_seconds.
var peek_fade_seconds: int = 5
## Client-only override for the local player's name color in chat (peek +
## full feed). Empty string = use the default hashed color. Pure vanity, not
## shipped to other clients. Persisted to ClientState.settings under
## chat / self_name_color (hex with leading "#").
var self_name_color_override: String = ""

var _public_label_world: String = "World"
var _public_label_team: String = "Team"
var _public_label_guild: String = "Guild"

var fade_out_tween: Tween
var _full_feed_tween: Tween
var _chat_toggle_icon: TextureRect
#endregion


#region Nodes
@onready var peek_feed: VBoxContainer = $PeekFeed
@onready var full_feed: Control = $FullFeed
## The visible chat block (sidebar + chat panel). FullFeed itself spans most
## of the screen with an offset, so we check this tighter rect for the
## click-outside-to-close behaviour.
@onready var full_feed_content: Control = $FullFeed/Control

@onready var peek_feed_text_display: RichTextLabel = $PeekFeed/MessageDisplay
@onready var peek_feed_message_edit: LineEdit = $PeekFeed/MessageEdit
@onready var fade_out_timer: Timer = $PeekFeed/FadeOutTimer

@onready var full_feed_text_display: RichTextLabel = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/RichTextLabel
@onready var full_feed_message_edit: LineEdit = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer2/LineEdit

@onready var dm_container: VBoxContainer = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/ScrollContainer/VBoxContainer

@onready var system_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/SystemChatButton
@onready var all_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/AllChatButton
@onready var world_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/WorldChatButton
@onready var team_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/TeamChatButton
@onready var guild_chat_button: Button = $FullFeed/Control/HBoxContainer/ContactPanel/VBoxContainer/GuildChatButton
@onready var send_button: Button = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer2/Button

@onready var chat_title_label: Label = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer/ChatTitleLabel
@onready var settings_button: Button = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer/SettingsButton

# Settings panel nodes — laid out in chat_menu.tscn under ChatPanel/VBoxContainer2/SettingsPanel.
@onready var settings_panel: ScrollContainer = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel
@onready var settings_blocked_list: VBoxContainer = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel/SettingsContent/BlockedScroll/BlockedList
@onready var settings_blocked_empty: Label = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel/SettingsContent/BlockedScroll/BlockedList/EmptyLabel
@onready var settings_peek_show_world: CheckBox = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel/SettingsContent/PeekShowWorld
@onready var settings_peek_show_dm: CheckBox = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel/SettingsContent/PeekShowDM
@onready var settings_peek_show_system: CheckBox = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel/SettingsContent/PeekShowSystem
@onready var settings_peek_fade_option: OptionButton = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel/SettingsContent/PeekFadeRow/PeekFadeOption
@onready var settings_name_color_row: HBoxContainer = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/SettingsPanel/SettingsContent/NameColorRow

@onready var full_feed_input_row: HBoxContainer = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HBoxContainer2
@onready var full_feed_sep_above_input: HSeparator = $FullFeed/Control/HBoxContainer/ChatPanel/VBoxContainer2/HSeparator2
#endregion


func _ready() -> void:
	ClientState.dm_requested.connect(open_dm)

	Client.subscribe(&"chat.message", _on_chat_message)
	Client.subscribe(&"chat.typing", _on_chat_typing)
	Client.request_data(&"chat.bootstrap", Callable(), {"limit": BOOTSTRAP_LIMIT}, InstanceClient.current.name)
	# Hydrate the local block list. Server is authoritative (it already drops
	# blocked senders before the push), but the client copy lets us catch
	# the brief race between a Block click and any messages the server may
	# have already in flight.
	Client.request_data(&"social.block.list", _on_block_list_received, {}, InstanceClient.current.name)

	peek_feed_message_edit.text_submitted.connect(_on_text_submitted.bind(peek_feed_message_edit))
	full_feed_message_edit.text_submitted.connect(_on_text_submitted.bind(full_feed_message_edit))

	# Typing indicator: notify the server when the local user starts/stops
	# composing. Idempotent server-side; we also de-dupe locally via
	# _typing_state so flipping focus quickly doesn't spam packets.
	peek_feed_message_edit.focus_entered.connect(_on_chat_input_focus_changed.bind(true))
	peek_feed_message_edit.focus_exited.connect(_on_chat_input_focus_changed.bind(false))
	full_feed_message_edit.focus_entered.connect(_on_chat_input_focus_changed.bind(true))
	full_feed_message_edit.focus_exited.connect(_on_chat_input_focus_changed.bind(false))

	# Mobile: lift the chat above the on-screen keyboard while composing in the full feed
	# (its input is at the screen bottom; the peek input sits up top and stays visible).
	full_feed_message_edit.focus_entered.connect(func() -> void: set_process(true))
	full_feed_message_edit.focus_exited.connect(_reset_keyboard_lift)
	set_process(false)

	_public_label_world = world_chat_button.text
	_public_label_team = team_chat_button.text
	_public_label_guild = guild_chat_button.text

	world_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_WORLD))
	team_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_TEAM))
	guild_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_GUILD))
	system_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_SYSTEM))
	all_chat_button.pressed.connect(func() -> void: open_channel(CHANNEL_ALL))

	send_button.pressed.connect(_on_send_button_pressed)
	settings_button.pressed.connect(_toggle_settings_panel)
	# Keep the in-panel block list in sync with profile-driven (un)blocks.
	ClientState.blocked_ids_changed.connect(_on_blocked_ids_changed_for_settings)
	_init_settings_panel()

	current_conversation_id = ChatConstants.channel_conversation_id(CHANNEL_WORLD)
	_ensure_conversation_exists(current_conversation_id)

	_sync_channel_buttons()
	_update_public_button_labels()

	peek_feed.show()
	full_feed.hide()
	# Also start the fade countdown at spawn, so the initial (empty) peek doesn't linger forever waiting
	# for the first message to trigger it.
	_start_peek_fade()

	_build_chat_toggle()
	_apply_input_mode()
	ClientState.input_changed.connect(func(_t: InputComponent.InputType) -> void: _apply_input_mode())
	# PC: hide the compose field again when focus leaves it (Enter re-opens).
	peek_feed_message_edit.focus_exited.connect(_apply_input_mode)

	_refresh_full_feed()
	_refresh_title_and_input()
	_update_input_enabled_state()


## PC: the peek feed is read-only SCENERY — fighting near the top-left corner
## must neither unfade it, open it, nor (via InputComponent's UI gate) block
## attacks. Compose with Enter; the full panel opens from the bubble button.
## Touch keeps tap-to-open: there's no mouse to aim with, taps are deliberate.
func _apply_input_mode() -> void:
	var touch: bool = ClientState.input_type == InputComponent.InputType.TOUCH
	var filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP if touch else Control.MOUSE_FILTER_IGNORE
	peek_feed.mouse_filter = filter
	peek_feed_text_display.mouse_filter = filter
	peek_feed_message_edit.visible = touch or peek_feed_message_edit.has_focus()


## Mobile keyboard lift: while composing in the full feed on a touch device, shift the
## whole chat up by the on-screen keyboard's height so the bottom input field isn't hidden
## behind it. _process runs only while that field is focused (enabled on focus_entered);
## the keyboard animates in, so we poll its height each frame. NOTE: needs on-device tuning
## — if the lift is off, the keyboard height may need scaling by the content/stretch factor.
func _process(_delta: float) -> void:
	if ClientState.input_type != InputComponent.InputType.TOUCH or not full_feed_message_edit.has_focus():
		_reset_keyboard_lift()
		return
	_set_keyboard_lift(float(DisplayServer.virtual_keyboard_get_height()))


func _set_keyboard_lift(px: float) -> void:
	offset_top = -px
	offset_bottom = -px


func _reset_keyboard_lift() -> void:
	offset_top = 0.0
	offset_bottom = 0.0
	set_process(false)


## The one deliberate chat click-target on every platform: a small bubble
## pinned under the peek block toggling the full panel.
var _chat_toggle: Button

func _build_chat_toggle() -> void:
	_chat_toggle = Button.new()
	_chat_toggle.custom_minimum_size = Vector2(40, 40)
	_chat_toggle.focus_mode = Control.FOCUS_NONE
	_chat_toggle.tooltip_text = "Open chat  (Enter to type)"
	_chat_toggle.position = Vector2(10, 218)
	_chat_toggle.pressed.connect(_on_chat_toggle_pressed)
	add_child(_chat_toggle)
	_chat_toggle_icon = PixelIcon.mount(_chat_toggle, CHAT_ICON)
	# The bubble is the OPENER — the full panel has its own Close button, so
	# hide it while the panel is up (it drew on top of the panel otherwise).
	full_feed.visibility_changed.connect(func() -> void:
		_chat_toggle.visible = not full_feed.visible
	)


func _on_chat_toggle_pressed() -> void:
	if full_feed.visible:
		_on_close_button_pressed()
		return
	peek_feed.hide()
	_show_full_feed()
	_sync_channel_buttons()
	_update_public_button_labels()
	_refresh_full_feed()
	_refresh_title_and_input()
	_update_input_enabled_state()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"player_chat"):
		if not full_feed.visible and not peek_feed_message_edit.has_focus():
			get_viewport().set_input_as_handled()
			accept_event()
			_open_peek_for_typing()

	if event is InputEventMouseButton and event.is_pressed():
		var mouse_position: Vector2 = event.global_position

		if peek_feed_message_edit.has_focus() and not peek_feed_message_edit.get_global_rect().has_point(mouse_position):
			peek_feed_message_edit.release_focus()
		
		if full_feed_message_edit.has_focus() and not full_feed_message_edit.get_global_rect().has_point(mouse_position):
			full_feed_message_edit.release_focus()

		if full_feed.visible and not full_feed_content.get_global_rect().has_point(mouse_position):
			_on_close_button_pressed()


func _open_peek_for_typing() -> void:
	peek_feed.show()
	_reset_peek_view()
	peek_feed_message_edit.show() # hidden on PC until composing
	peek_feed_message_edit.grab_focus()
	fade_out_timer.stop()


#region Incoming
func _on_block_list_received(payload: Dictionary) -> void:
	if not payload.get("ok", false):
		return
	var entries_v: Variant = payload.get("entries", [])
	if entries_v is Array:
		ClientState.set_blocked_ids(entries_v)


func _on_chat_message(message: Dictionary) -> void:
	if message.is_empty():
		return

	var text: String = str(message.get("text", ""))
	var sender_name: String = str(message.get("name", ""))
	var sender_id: int = int(message.get("id", 0))
	var sender_peer_id: int = int(message.get("peer_id", 0))

	# Block filter: silently drop messages from anyone the local user has
	# blocked. Server already filters at broadcast time; this is the safety
	# net for messages that slipped through before the block hit.
	if sender_id > 0 and ClientState.blocked_ids.has(sender_id):
		return
	var sender_title: String = str(message.get("title", ""))
	var sender_guild: String = str(message.get("guild_name", ""))
	var msg_id: int = int(message.get("msg_id", 0))
	var time_ms: int = int(message.get("time_ms", 0))
	var is_history: bool = bool(message.get("is_history", false))

	if time_ms <= 0:
		time_ms = int(Time.get_unix_time_from_system() * 1000.0)

	var convo_id: String = str(message.get("conversation_id", ""))
	if convo_id.is_empty():
		var channel: int = int(message.get("channel", CHANNEL_WORLD))
		convo_id = ChatConstants.channel_conversation_id(channel)

	_ensure_conversation_exists(convo_id)

	if msg_id > 0 and _is_duplicate_msg(convo_id, msg_id):
		return

	if convo_id.begins_with("dm:"):
		var self_id_dm: int = int(ClientState.player_id)
		var other_id_dm: int = _dm_other_id_from_conversation(convo_id, self_id_dm)
		if other_id_dm > 0:
			if sender_id == other_id_dm and not sender_name.is_empty():
				dm_name_by_player_id[other_id_dm] = sender_name
			_ensure_dm_button(convo_id, other_id_dm)

	var self_player_id: int = int(ClientState.player_id)
	var is_self: bool = sender_id == self_player_id
	var is_system: bool = sender_id == ChatConstants.SYSTEM_SENDER_ID

	var record: Dictionary = {
		"id": sender_id,
		"name": sender_name,
		"title": sender_title,
		"guild_name": sender_guild,
		"text": text,
		"time_ms": time_ms,
		"msg_id": msg_id,
		"is_self": is_self,
		"is_system": is_system,
		"convo_id": convo_id,
	}

	var convo_records: Array = raw_messages_by_conversation[convo_id]
	convo_records.append(record)
	# Keep history ordered by time so backfilled messages land in the right
	# place. The common case (steady-state pushes) is already sorted, so
	# insertion-sort cost stays near-zero.
	if convo_records.size() >= 2:
		var i: int = convo_records.size() - 1
		while i > 0 and int(convo_records[i - 1]["time_ms"]) > time_ms:
			convo_records[i] = convo_records[i - 1]
			i -= 1
		convo_records[i] = record

	var is_viewing: bool = full_feed.visible and (current_conversation_id == convo_id or current_conversation_id == ALL_CONVERSATION_ID)

	# Count as unread when we're NOT actually looking at it — is_viewing already folds in
	# full_feed.visible, so a closed feed (even on the last-opened DM) correctly badges new messages.
	if not is_history and not is_self and not is_viewing:
		_inc_unread(convo_id)

	if not is_history and _should_show_in_peek(convo_id):
		var peek_line: String = _format_message_peek(convo_id, sender_id, sender_name, text)
		peek_feed_text_display.append_text(peek_line)
		peek_feed_text_display.newline()

	# Overhead chat bubble: only on live WORLD messages (proximity chat).
	# DMs/guild/system stay UI-only so they don't leak through the world.
	var is_world_channel: bool = convo_id == ChatConstants.channel_conversation_id(CHANNEL_WORLD)
	if not is_history and is_world_channel and sender_peer_id > 0 and InstanceClient.current != null:
		var sender_player: Player = InstanceClient.current.players_by_peer_id.get(sender_peer_id, null)
		if sender_player != null and is_instance_valid(sender_player):
			sender_player.show_overhead(text)

	if is_viewing:
		# Re-render the whole view: collapse + dividers depend on neighbours
		# and the cheapest correct way to handle out-of-order history + the
		# ALL aggregate view is to rebuild.
		_refresh_full_feed()
		if is_self:
			# Discord-style: when the local player sends a message, jump the
			# scroll to the bottom so they always see what they just typed,
			# even if they had scrolled up to read history.
			full_feed_text_display.scroll_to_line.call_deferred(full_feed_text_display.get_line_count())
	else:
		if not is_history and not full_feed.visible:
			_reset_peek_view()
			peek_feed_text_display.show()
			_start_peek_fade()

	_update_public_button_labels()
#endregion


#region Peek fade
func _on_fade_out_timer_timeout() -> void:
	if peek_feed_message_edit.has_focus():
		_start_peek_fade()
		return

	if fade_out_tween != null:
		fade_out_tween.kill()

	fade_out_tween = create_tween()
	fade_out_tween.tween_property(peek_feed, ^"modulate:a", 0.0, 0.3)


func _on_peek_feed_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and peek_feed.modulate.a < 1.0:
		_reset_peek_view()
		_start_peek_fade()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		peek_feed.hide()
		_show_full_feed()

		_sync_channel_buttons()
		_update_public_button_labels()

		_refresh_full_feed()
		_refresh_title_and_input()
		_update_input_enabled_state()


func _on_close_button_pressed() -> void:
	peek_feed.show()
	_reset_peek_view()
	_start_peek_fade()
	_hide_full_feed()


func _reset_peek_view() -> void:
	if fade_out_tween != null and fade_out_tween.is_running():
		fade_out_tween.kill()
	peek_feed.modulate.a = 1.0


## Kick off the peek fade-out countdown, honouring the user-chosen duration.
## When peek_fade_seconds == 0 the peek is "never fade" — we just skip
## starting the timer, so the feed stays visible until explicitly dismissed.
func _start_peek_fade() -> void:
	if peek_fade_seconds <= 0:
		fade_out_timer.stop()
		return
	fade_out_timer.wait_time = float(peek_fade_seconds)
	fade_out_timer.start()


## Open the full feed with a slide-in-from-left + fade, mirroring the right-side menu overlay so both
## read as deliberately "opened" rather than popping in. Kills any in-flight tween for fast re-toggles.
func _show_full_feed() -> void:
	# Navigating to any channel/DM always lands on the feed, never a stale Chat-options view.
	_set_settings_open(false)
	# Already open (e.g. switching channels from the sidebar) — don't replay the slide.
	if full_feed.visible:
		return
	if _full_feed_tween != null and _full_feed_tween.is_valid():
		_full_feed_tween.kill()
	full_feed.visible = true
	full_feed.modulate.a = 0.0
	full_feed_content.position.x = -FULL_FEED_SLIDE
	_full_feed_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_full_feed_tween.tween_property(full_feed, ^"modulate:a", 1.0, 0.18)
	_full_feed_tween.tween_property(full_feed_content, ^"position:x", 0.0, 0.18)


## The open effect in reverse: slide back out to the left + fade, THEN hide.
func _hide_full_feed() -> void:
	if _full_feed_tween != null and _full_feed_tween.is_valid():
		_full_feed_tween.kill()
	_full_feed_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_full_feed_tween.tween_property(full_feed, ^"modulate:a", 0.0, 0.16)
	_full_feed_tween.tween_property(full_feed_content, ^"position:x", -FULL_FEED_SLIDE, 0.16)
	_full_feed_tween.chain().tween_callback(full_feed.hide)
#endregion


func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	ClientState.player_profile_requested.emit(str(meta).to_int())


#region Sending
func _on_text_submitted(new_text: String, line_edit: LineEdit) -> void:
	line_edit.clear()
	line_edit.release_focus()

	var is_peek: bool = (line_edit == peek_feed_message_edit)
	if is_peek:
		_start_peek_fade()

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

	if current_conversation_id == ALL_CONVERSATION_ID:
		# Composing from the aggregate ALL view doesn't have an obvious
		# target — default to WORLD (the public broadcast). The user can
		# switch tabs for guild / DM.
		_send_channel_message(CHANNEL_WORLD, new_text)
		return

	if current_conversation_id.begins_with("guild:") and _get_active_guild_id() <= 0:
		_show_full_notice("You are not in a guild.")
		return

	if current_channel == CHANNEL_TEAM:
		_show_full_notice("Team chat not implemented yet.")
		return

	_send_channel_message(current_channel, new_text)


func _on_send_button_pressed() -> void:
	var text: String = full_feed_message_edit.text
	if text.strip_edges().is_empty():
		return
	# Re-use the normal submit pipeline so behaviour stays identical to
	# pressing Enter.
	_on_text_submitted(text, full_feed_message_edit)


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

	elif channel == CHANNEL_ALL:
		current_conversation_id = ALL_CONVERSATION_ID

	else:
		current_conversation_id = ChatConstants.channel_conversation_id(CHANNEL_WORLD)

	_clear_unread(current_conversation_id)

	_show_full_feed()
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

	_show_full_feed()
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

	_show_full_feed()
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

	var records: Array = _records_for_current_view()
	var prev: Dictionary = {}
	var show_channel_prefix: bool = current_conversation_id == ALL_CONVERSATION_ID

	for record: Dictionary in records:
		var block: String = _format_message_block(record, prev, show_channel_prefix)
		if not block.is_empty():
			full_feed_text_display.append_text(block)
			full_feed_text_display.newline()
		prev = record


## Returns the records to draw for the active conversation. For the ALL
## synthetic view we merge every real conversation in time order; otherwise
## we just hand back the per-conversation log.
func _records_for_current_view() -> Array:
	if current_conversation_id != ALL_CONVERSATION_ID:
		return raw_messages_by_conversation.get(current_conversation_id, [])

	var merged: Array = []
	for convo_id: String in raw_messages_by_conversation.keys():
		if convo_id == ALL_CONVERSATION_ID:
			continue
		for r: Dictionary in raw_messages_by_conversation[convo_id]:
			merged.append(r)

	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("time_ms", 0)) < int(b.get("time_ms", 0))
	)
	return merged


func _refresh_title_and_input() -> void:
	if chat_title_label != null:
		chat_title_label.text = _title_for_current()


func _title_for_current() -> String:
	if current_conversation_id == ALL_CONVERSATION_ID:
		return "All"

	if current_conversation_id.begins_with("dm:"):
		var other_id: int = current_dm_other_id
		if other_id <= 0:
			other_id = _dm_other_id_from_conversation(current_conversation_id, int(ClientState.player_id))
		var title_text: String = str(dm_name_by_player_id.get(other_id, ""))
		return title_text if not title_text.is_empty() else "DM %d" % other_id

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
## Builds the full per-message block:
## - optional centered grey timestamp divider (Discord-style separator)
## - optional name/title/guild header (suppressed on same-sender collapse)
## - body line
## Self messages right-align both header and body.
func _format_message_block(record: Dictionary, prev: Dictionary, show_channel_prefix: bool) -> String:
	var parts: PackedStringArray = PackedStringArray()

	var time_ms: int = int(record.get("time_ms", 0))
	var prev_time_ms: int = int(prev.get("time_ms", 0)) if not prev.is_empty() else 0
	var prev_sender_id: int = int(prev.get("id", 0)) if not prev.is_empty() else 0
	var prev_convo_id: String = str(prev.get("convo_id", ""))

	var should_show_divider: bool = prev.is_empty() or (time_ms - prev_time_ms) >= TIMESTAMP_DIVIDER_GAP_MS
	if should_show_divider:
		parts.append("[center][color=%s]%s[/color][/center]" % [SUBTLE_COLOR, _format_timestamp(time_ms)])

	var sender_id: int = int(record.get("id", 0))
	var same_sender: bool = (not prev.is_empty()
		and prev_sender_id == sender_id
		and prev_convo_id == str(record.get("convo_id", ""))
		and (time_ms - prev_time_ms) < COLLAPSE_WINDOW_MS
	)
	# A new divider visually resets the "thread" — always show the header
	# again after one so the reader knows who is speaking.
	var should_show_header: bool = should_show_divider or not same_sender

	var is_self: bool = bool(record.get("is_self", false))
	var body_text: String = str(record.get("text", ""))

	if should_show_header:
		var header: String = _format_header(record, show_channel_prefix)
		if is_self:
			header = "[right]%s[/right]" % header
		parts.append(header)

	var body_line: String = body_text
	if is_self:
		body_line = "[right]%s[/right]" % body_text
	parts.append(body_line)

	return "\n".join(parts)


func _format_header(record: Dictionary, show_channel_prefix: bool) -> String:
	var sender_id: int = int(record.get("id", 0))
	var sender_name: String = str(record.get("name", ""))
	var title: String = str(record.get("title", ""))
	var guild_name: String = str(record.get("guild_name", ""))
	var is_self: bool = bool(record.get("is_self", false))
	var is_system: bool = bool(record.get("is_system", false))

	var name_color: String
	if is_system:
		name_color = SYSTEM_NAME_COLOR
	elif is_self:
		# Client-only override picked in chat settings. Empty string falls
		# back to the default neutral self-tone so own messages don't compete
		# with the hashed colour palette used for everyone else.
		name_color = self_name_color_override if not self_name_color_override.is_empty() else SELF_NAME_COLOR
	else:
		name_color = _hashed_name_color(sender_id, sender_name)

	var name_chunk: String
	if is_system:
		name_chunk = "[color=%s]%s[/color]" % [name_color, sender_name]
	else:
		name_chunk = "[color=%s][url=%d]%s[/url][/color]" % [name_color, sender_id, sender_name]

	var pieces: PackedStringArray = PackedStringArray()

	if show_channel_prefix:
		var convo_id: String = str(record.get("convo_id", ""))
		var prefix: String = _channel_prefix_for_conversation(convo_id)
		if not prefix.is_empty():
			var pc: String = _tag_color_for_conversation(convo_id)
			pieces.append("[color=%s][%s][/color]" % [pc, prefix])

	pieces.append(name_chunk)

	if not guild_name.is_empty():
		pieces.append("[color=%s](%s)[/color]" % [SUBTLE_COLOR, guild_name])

	if not title.is_empty():
		pieces.append("[color=%s]« %s »[/color]" % [TITLE_COLOR, title])

	return " ".join(pieces)


## HSV → hex using a stable hash of the sender so the same person always
## colours the same. Keeps S and V high so the name reads cleanly against
## the dark chat background.
func _hashed_name_color(sender_id: int, sender_name: String) -> String:
	var seed_value: int = sender_id if sender_id != 0 else hash(sender_name)
	var hue: float = float(absi(seed_value) % 360) / 360.0
	var color: Color = Color.from_hsv(hue, 0.55, 1.0)
	return "#" + color.to_html(false)


func _format_timestamp(time_ms: int) -> String:
	if time_ms <= 0:
		return ""
	@warning_ignore("integer_division")
	var unix_sec: int = time_ms / 1000
	var t: Dictionary = Time.get_time_dict_from_unix_time(unix_sec)
	return "%02d:%02d" % [int(t.get("hour", 0)), int(t.get("minute", 0))]


func _format_message_peek(convo_id: String, sender_id: int, sender_name: String, text: String) -> String:
	var name_color: String
	if sender_id == ChatConstants.SYSTEM_SENDER_ID:
		name_color = SYSTEM_NAME_COLOR
	elif sender_id == int(ClientState.player_id):
		name_color = self_name_color_override if not self_name_color_override.is_empty() else SELF_NAME_COLOR
	else:
		name_color = _hashed_name_color(sender_id, sender_name)

	var name_chunk: String
	if sender_id == ChatConstants.SYSTEM_SENDER_ID:
		name_chunk = "[color=%s]%s[/color]" % [name_color, sender_name]
	else:
		name_chunk = "[color=%s][url=%d]%s[/url][/color]" % [name_color, sender_id, sender_name]

	var base: String = "%s: %s" % [name_chunk, text]

	var prefix: String = _peek_prefix_for_conversation(convo_id)
	if prefix.is_empty():
		return base

	var tag_color: String = _tag_color_for_conversation(convo_id)
	return "[color=%s][%s][/color] %s" % [tag_color, prefix, base]


## Short channel-prefix shown in the ALL view so the reader can see at a
## glance which channel produced each line. DM gets the partner's name when
## known so two DM threads don't collide visually.
func _channel_prefix_for_conversation(convo_id: String) -> String:
	if convo_id.begins_with("dm:"):
		var self_id: int = int(ClientState.player_id)
		var other_id: int = _dm_other_id_from_conversation(convo_id, self_id)
		var dm_name: String = str(dm_name_by_player_id.get(other_id, ""))
		return ("DM:" + dm_name) if not dm_name.is_empty() else "DM"
	if convo_id.begins_with("guild:"):
		return "GUILD"
	if _is_system_conversation(convo_id):
		return "SYS"
	if convo_id == ChatConstants.channel_conversation_id(CHANNEL_WORLD):
		return "WORLD"
	if convo_id == ChatConstants.channel_conversation_id(CHANNEL_TEAM):
		return "TEAM"
	return "CHAT"


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
	if not raw_messages_by_conversation.has(convo_id):
		raw_messages_by_conversation[convo_id] = []

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

	var button_text: String = str(dm_name_by_player_id.get(other_id, ""))
	if button_text.is_empty():
		button_text = "DM %d" % other_id

	var unread: int = _get_unread(convo_id)
	button.text = ("(%d) %s" % [unread, button_text]) if unread > 0 else button_text


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
	_update_chat_toggle_icon()


func _inc_unread(convo_id: String) -> void:
	_set_unread(convo_id, _get_unread(convo_id) + 1)


func _clear_unread(convo_id: String) -> void:
	_set_unread(convo_id, 0)


## True if any DM conversation has unread messages — drives the HUD toggle's exclamation icon. We badge
## ONLY DMs (directed at the player); public/guild/system stream through the peek and would just be noise.
func _has_unread_dm() -> bool:
	for convo_id: String in unread_by_conversation:
		if convo_id.begins_with("dm:") and unread_by_conversation[convo_id] > 0:
			return true
	return false


## Swap the closed-state HUD toggle between the plain and exclamation chat glyphs based on unread DMs.
func _update_chat_toggle_icon() -> void:
	if not is_instance_valid(_chat_toggle_icon):
		return
	PixelIcon.set_art(_chat_toggle_icon, CHAT_ICON_UNREAD if _has_unread_dm() else CHAT_ICON)


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
	if convo_id.begins_with("dm:"):
		return not mute_peek_dm

	if convo_id == ChatConstants.channel_conversation_id(CHANNEL_WORLD):
		return not mute_peek_world

	if _is_system_conversation(convo_id):
		return not mute_peek_system

	return true


func _handle_local_mute_command(args: PackedStringArray) -> void:
	if args.size() < 2:
		_system_echo("Usage: /mute dm|world|sys|off")
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
	elif what == "off":
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

	# Cheap client-side guard: don't even round-trip if we know we've blocked
	# the target. Server still validates authoritatively.
	if ClientState.blocked_ids.has(other_id):
		_show_full_notice("You have this player blocked. Unblock them to send a DM.")
		return

	Client.request_data(
		&"chat.message.send",
		_on_chat_send_result,
		{"text": text, "dm_target_id": other_id},
		InstanceClient.current.name
	)


## Surface backend rejections (blocks, mutes, rate-limits, etc.) as a notice
## in the active chat view so the player understands why their message
## didn't go out.
func _on_chat_send_result(result: Dictionary) -> void:
	if result.is_empty() or result.get("ok", true):
		return
	var msg: String = str(result.get("message", "Message failed."))
	_show_full_notice(msg)


## Tracks whether the server believes the local player is currently typing.
## Both chat inputs share this flag — focus moving between peek and full
## feed doesn't re-fire the network call.
var _typing_state_sent: bool = false


func _on_chat_input_focus_changed(now_focused: bool) -> void:
	# A focus signal fires for the leaving control before the entering one,
	# so check whether ANY chat input still has focus before declaring stop.
	var any_focused: bool = (peek_feed_message_edit.has_focus()
		or full_feed_message_edit.has_focus())
	# Defer the actual decision one frame so the just-focused field has
	# registered its focus state by the time we read it.
	_set_typing_state.call_deferred(now_focused or any_focused)


func _set_typing_state(should_be_typing: bool) -> void:
	# Re-read focus after the deferred bounce — the cheap dedupe below
	# handles redundant transitions either way.
	var actually_typing: bool = should_be_typing and (
		peek_feed_message_edit.has_focus()
		or full_feed_message_edit.has_focus()
	)
	if actually_typing == _typing_state_sent:
		return
	_typing_state_sent = actually_typing
	Client.request_data(
		&"chat.typing.set",
		Callable(),
		{"typing": actually_typing},
		InstanceClient.current.name
	)
	# Server skips the sender when broadcasting chat.typing (no need to
	# round-trip our own state), so the local player never receives a push
	# for itself. Drive the bubble locally instead — feels weird to see the
	# indicator on others but not yourself.
	if ClientState.local_player != null and is_instance_valid(ClientState.local_player):
		ClientState.local_player.set_typing(actually_typing)
		# Kill player input while composing so the sticks/keys don't move or attack —
		# fixes mobile "I keep attacking with the stick while the keyboard is up".
		ClientState.local_player.set_input_active(not actually_typing)


func _on_chat_typing(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var sender_peer_id: int = int(payload.get("peer_id", 0))
	var sender_id: int = int(payload.get("id", 0))
	if sender_peer_id <= 0:
		return
	# Block list: don't render an indicator for someone we've blocked.
	# Server already filters but this is the same belt-and-braces pattern
	# we use for chat.message.
	if sender_id > 0 and ClientState.blocked_ids.has(sender_id):
		return
	if InstanceClient.current == null:
		return
	var sender_player: Player = InstanceClient.current.players_by_peer_id.get(sender_peer_id, null)
	if sender_player == null or not is_instance_valid(sender_player):
		return
	sender_player.set_typing(bool(payload.get("typing", false)))
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


#region Settings panel
## Settings panel is laid out in chat_menu.tscn under
## ChatPanel/VBoxContainer2/SettingsPanel. This region only wires controls,
## populates the dynamic content (block list buttons, name-colour swatches),
## and persists choices to ClientState.settings.

const SETTINGS_SECTION: StringName = &"chat"
const SETTINGS_PEEK_FADE_KEY: StringName = &"peek_fade_seconds"
const SETTINGS_SELF_COLOR_KEY: StringName = &"self_name_color"
const SETTINGS_PEEK_SHOW_WORLD: StringName = &"peek_show_world"
const SETTINGS_PEEK_SHOW_DM: StringName = &"peek_show_dm"
const SETTINGS_PEEK_SHOW_SYSTEM: StringName = &"peek_show_system"

## Peek fade duration presets shown in the OptionButton.
## Label → seconds (0 means "never fade").
const PEEK_FADE_PRESETS: Array[Dictionary] = [
	{"label": "3 seconds", "seconds": 3},
	{"label": "5 seconds", "seconds": 5},
	{"label": "10 seconds", "seconds": 10},
	{"label": "Never fade", "seconds": 0},
]

## Curated swatches for the "Your name color" picker. Empty hex means "use
## the default neutral self-tone" — first slot is always the reset.
const NAME_COLOR_SWATCHES: Array = [
	"",          # default
	"#ffd36b",   # gold
	"#7dff9a",   # mint
	"#66d9ff",   # cyan
	"#d56bff",   # violet
	"#ff8e8e",   # rose
	"#ffffff",   # white
]

## Display-name cache for blocked players keyed by player_id. Populated when
## the settings panel fetches social.block.list so the buttons read better
## than "Player #42".
var _blocked_names_by_id: Dictionary[int, String]


func _init_settings_panel() -> void:
	# Hydrate the persisted prefs first so the controls reflect saved state.
	_load_chat_settings()

	# Per-channel peek toggles.
	settings_peek_show_world.button_pressed = not mute_peek_world
	settings_peek_show_world.toggled.connect(func(pressed: bool) -> void:
		mute_peek_world = not pressed
		_save_chat_setting(SETTINGS_PEEK_SHOW_WORLD, pressed)
	)
	settings_peek_show_dm.button_pressed = not mute_peek_dm
	settings_peek_show_dm.toggled.connect(func(pressed: bool) -> void:
		mute_peek_dm = not pressed
		_save_chat_setting(SETTINGS_PEEK_SHOW_DM, pressed)
	)
	settings_peek_show_system.button_pressed = not mute_peek_system
	settings_peek_show_system.toggled.connect(func(pressed: bool) -> void:
		mute_peek_system = not pressed
		_save_chat_setting(SETTINGS_PEEK_SHOW_SYSTEM, pressed)
	)

	# Peek fade preset OptionButton.
	settings_peek_fade_option.clear()
	var selected_index: int = 0
	for i: int in PEEK_FADE_PRESETS.size():
		var preset: Dictionary = PEEK_FADE_PRESETS[i]
		settings_peek_fade_option.add_item(str(preset["label"]), i)
		if int(preset["seconds"]) == peek_fade_seconds:
			selected_index = i
	settings_peek_fade_option.select(selected_index)
	_apply_peek_fade_seconds()
	settings_peek_fade_option.item_selected.connect(func(index: int) -> void:
		var preset: Dictionary = PEEK_FADE_PRESETS[index]
		peek_fade_seconds = int(preset["seconds"])
		_apply_peek_fade_seconds()
		_save_chat_setting(SETTINGS_PEEK_FADE_KEY, peek_fade_seconds)
	)

	# Name-colour swatches (programmatic because they're a uniform grid of
	# coloured buttons — fits the data-driven SWATCHES constant better than
	# duplicating 7 nodes in the scene).
	_build_name_color_swatches()


func _build_name_color_swatches() -> void:
	for swatch_v: Variant in NAME_COLOR_SWATCHES:
		var swatch_hex: String = str(swatch_v)
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(28, 28)
		btn.toggle_mode = true
		btn.button_pressed = (swatch_hex == self_name_color_override)
		btn.tooltip_text = "Default" if swatch_hex.is_empty() else swatch_hex
		# Display-only stylebox showing the swatch colour. Empty hex shows a
		# faint "auto" diamond instead of a coloured square.
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.35, 0.35, 0.4, 0.5) if swatch_hex.is_empty() else Color(swatch_hex)
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_right = 4
		sb.corner_radius_bottom_left = 4
		btn.add_theme_stylebox_override(&"normal", sb)
		btn.add_theme_stylebox_override(&"hover", sb)
		btn.add_theme_stylebox_override(&"pressed", sb)
		# Border around the picked one so the choice is visible.
		var sb_picked: StyleBoxFlat = sb.duplicate()
		sb_picked.border_color = Color(1, 1, 1, 0.9)
		sb_picked.border_width_left = 2
		sb_picked.border_width_top = 2
		sb_picked.border_width_right = 2
		sb_picked.border_width_bottom = 2
		btn.add_theme_stylebox_override(&"pressed", sb_picked)
		btn.toggled.connect(func(pressed: bool) -> void:
			if not pressed:
				# Re-press the default so we always have an explicit pick.
				btn.set_pressed_no_signal(swatch_hex == self_name_color_override)
				return
			_set_self_name_color(swatch_hex)
		)
		settings_name_color_row.add_child(btn)


func _set_self_name_color(hex: String) -> void:
	if hex == self_name_color_override:
		return
	self_name_color_override = hex
	_save_chat_setting(SETTINGS_SELF_COLOR_KEY, hex)
	# Refresh swatches' pressed state and the chat view so existing messages
	# from "you" repaint immediately.
	for child: Node in settings_name_color_row.get_children():
		var b: Button = child as Button
		if b == null:
			continue
		b.set_pressed_no_signal(b.tooltip_text == ("Default" if hex.is_empty() else hex))
	_refresh_full_feed()


func _apply_peek_fade_seconds() -> void:
	# 0 = never fade. We accomplish that by giving the timer a huge wait_time
	# and never actually starting it (caller already gates with peek_fade_seconds).
	if peek_fade_seconds > 0:
		fade_out_timer.wait_time = float(peek_fade_seconds)


func _load_chat_settings() -> void:
	var section: Dictionary = ClientState.settings.data.get(SETTINGS_SECTION, {})
	if section.has(SETTINGS_PEEK_FADE_KEY):
		peek_fade_seconds = int(section[SETTINGS_PEEK_FADE_KEY])
	if section.has(SETTINGS_SELF_COLOR_KEY):
		self_name_color_override = str(section[SETTINGS_SELF_COLOR_KEY])
	if section.has(SETTINGS_PEEK_SHOW_WORLD):
		mute_peek_world = not bool(section[SETTINGS_PEEK_SHOW_WORLD])
	if section.has(SETTINGS_PEEK_SHOW_DM):
		mute_peek_dm = not bool(section[SETTINGS_PEEK_SHOW_DM])
	if section.has(SETTINGS_PEEK_SHOW_SYSTEM):
		mute_peek_system = not bool(section[SETTINGS_PEEK_SHOW_SYSTEM])


func _save_chat_setting(key: StringName, value: Variant) -> void:
	# ClientState.Settings.set_value needs the section dict to exist. The
	# autoload pre-fills sections from client_default_settings.cfg; if "chat"
	# isn't in there yet we create it on the fly so the first save sticks.
	if not ClientState.settings.data.has(SETTINGS_SECTION):
		ClientState.settings.data[SETTINGS_SECTION] = {}
	ClientState.settings.set_value(SETTINGS_SECTION, key, value)


func _toggle_settings_panel() -> void:
	_set_settings_open(not settings_panel.visible)


## Show/hide the Chat-options panel in place of the feed. Routing through one setter lets navigation
## (opening any channel/DM via _show_full_feed) force it closed, so the sidebar buttons always land on
## the feed instead of doing nothing while options are up.
func _set_settings_open(open: bool) -> void:
	settings_panel.visible = open
	# Feed + separator + input row swap places with the settings panel — same
	# chat-panel real estate, no overlay layering required.
	full_feed_text_display.visible = not open
	full_feed_sep_above_input.visible = not open
	full_feed_input_row.visible = not open
	settings_button.text = "Back" if open else "Settings"
	chat_title_label.text = "Chat options" if open else _title_for_current()
	if open:
		_refresh_block_list_request()


func _refresh_block_list_request() -> void:
	Client.request_data(
		&"social.block.list",
		_on_block_list_for_settings,
		{},
		InstanceClient.current.name
	)


func _on_block_list_for_settings(payload: Dictionary) -> void:
	if not payload.get("ok", false):
		return
	var entries_v: Variant = payload.get("entries", [])
	if not (entries_v is Array):
		return
	for entry: Dictionary in entries_v:
		_blocked_names_by_id[int(entry.get("id", 0))] = str(entry.get("name", ""))
	# Mirror to the central set so chat filter / profile menu stay in sync.
	ClientState.set_blocked_ids(entries_v)
	_rebuild_block_list_ui()


func _on_blocked_ids_changed_for_settings() -> void:
	if settings_panel != null and settings_panel.visible:
		_rebuild_block_list_ui()


func _rebuild_block_list_ui() -> void:
	if settings_blocked_list == null:
		return
	# Wipe existing rows, keep the empty-state label as a stable child.
	for child: Node in settings_blocked_list.get_children():
		if child == settings_blocked_empty:
			continue
		child.queue_free()

	var ids: Array = ClientState.blocked_ids.keys()
	settings_blocked_empty.visible = ids.is_empty()

	for id_v: Variant in ids:
		var blocked_id: int = int(id_v)
		var blocked_name: String = str(_blocked_names_by_id.get(blocked_id, ""))
		if blocked_name.is_empty():
			blocked_name = "Player #%d" % blocked_id
		var btn: Button = Button.new()
		btn.text = blocked_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Open the player's profile. Profile UI already handles the
		# Block/Unblock toggle, so no separate "Unblock" button here.
		btn.pressed.connect(ClientState.player_profile_requested.emit.bind(blocked_id))
		settings_blocked_list.add_child(btn)
#endregion
