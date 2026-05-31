extends Control


@export var name_label: Label

var cache: Dictionary[int, Dictionary]
## Most recent profile payload for the open target. Used so the Edit panel can
## seed its fields with the values currently shown.
var _current_profile: Dictionary

@onready var stats_text: RichTextLabel = $PanelContainer/HBoxContainer/StatsContainer/RichTextLabel
@onready var description_text: RichTextLabel = $PanelContainer/HBoxContainer/VBoxContainer2/RichTextLabel
@onready var player_character: AnimatedSprite2D = $PanelContainer/HBoxContainer/VBoxContainer2/Control/Control/AnimatedSprite2D

@onready var message_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/MessageButton
@onready var friend_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/FriendButton
@onready var invite_guild_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/InviteGuildButton

## Built lazily in _build_edit_ui — see the bottom of the file.
var _edit_button: Button
var _edit_panel: PanelContainer
var _title_option: OptionButton
var _animation_option: OptionButton
var _status_edit: TextEdit
var _status_counter: Label


func open_player_profile(player_id: int) -> void:
	#if cache.has(player_id):
		#print_debug("Cache used")
		#apply_profile(cache[player_id])
	#else:
	Client.request_data(
		&"profile.get",
		apply_profile,
		{"id": player_id},
		InstanceClient.current.name
	)


func apply_profile(profile: Dictionary) -> void:
	var stats: Dictionary = profile.get("stats", {})
	var player_name: String = profile.get("name", "No Name")
	var player_skin: int = profile.get("skin_id", 1)
	var animation: String = profile.get("animation", "idle")
	var description: String = profile.get("description", "Hello I'am new!")
	
	var is_self: bool = profile.get("self", false)
	description_text.clear()
	description_text.append_text(description)

	add_stats(stats)
	set_player_character(player_skin, animation)

	# Character name (nickname) + public account handle, e.g. "John  @guest1".
	# The permanent player_id (#id) is only sent to staff viewers.
	# Vanity title (if any) renders on its own line below as part of the same
	# label, so we don't need an extra scene node.
	name_label.text = player_name
	var account_name: String = profile.get("account_name", "")
	if not account_name.is_empty():
		name_label.text += "  @%s" % account_name
	if profile.get("staff_view", false):
		name_label.text += "  #%d" % int(profile.get("id", 0))
	if profile.get("guild_name", ""):
		name_label.text += " (%s)" % profile.get("guild_name", "")
	var title: String = profile.get("title", "")
	if not title.is_empty():
		# Plain Label can't render BBCode, so use a clean separator instead.
		name_label.text += "\n— %s —" % title

	_current_profile = profile

	message_button.visible = not is_self
	friend_button.visible = not is_self
	friend_button.disabled = is_self
	friend_button.text = "Add friend" if not profile.get("friend", false) else "Remove Friend"
	invite_guild_button.visible = profile.get("can_guild_invite", false)

	# Self-only Edit affordance for profile customization.
	if _edit_button == null:
		_build_edit_ui()
	_edit_button.visible = is_self
	if _edit_panel.get_meta(&"overlay").visible:
		# A second profile.get came in while editing — close the panel to avoid
		# stomping the user's in-flight edits with stale fields.
		_edit_panel.get_meta(&"overlay").hide()

	var is_friend: bool = profile.get("friend", false)
	if is_friend:
		friend_button.text = "Remove friend"
	else:
		friend_button.text = "Add friend"
		if friend_button.pressed.is_connected(_on_friend_button_pressed):
			friend_button.pressed.disconnect(_on_friend_button_pressed)
		friend_button.pressed.connect(
			_on_friend_button_pressed.bind(profile.get("id", 0)),
			CONNECT_ONE_SHOT
		)
	
	if not is_self:
		var target_id: int = int(profile.get("id", 0))
		if message_button.pressed.is_connected(_on_message_button_pressed):
			message_button.pressed.disconnect(_on_message_button_pressed)

		message_button.pressed.connect(
			_on_message_button_pressed.bind(target_id),
			CONNECT_ONE_SHOT
		)

	
	show()

	if profile.get("id", 0):
		cache[profile.get("id")] = profile


func add_stats(stats: Dictionary):
	stats_text.clear()
	stats_text.text = ""
	for stat_name: String in stats:
		#print("%s: %s" % [stat_name, stats[stat_name]])
		stats_text.append_text("%s: %s\n" % [stat_name, stats[stat_name]])


func set_player_character(skin_id: int, animation: String) -> void:
	var skin: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", skin_id)
	if not skin:
		return

	player_character.stop()
	player_character.sprite_frames = skin
	if player_character.sprite_frames.has_animation(animation):
		player_character.play(animation)


func _on_close_pressed() -> void:
	hide()


func _on_friend_button_pressed(player_id: int) ->void:
	Client.request_data(&"friend.request", Callable(), {"id": player_id})
	friend_button.disabled = true
	friend_button.text = "Added"


func _on_message_button_pressed(target_id: int) -> void:
	ClientState.dm_requested.emit(target_id)
	hide()


# ---------------------------------------------------------------------------
# Self-profile edit panel (title selector + status + animation).
# Built programmatically so we don't have to touch the scene file (hud.tscn-style
# unique_id pitfalls). The panel is a modal-ish overlay anchored to the profile
# control and toggled by the Edit button on the right-hand action column.
# ---------------------------------------------------------------------------


func _build_edit_ui() -> void:
	# The Edit button lives in the same action column as Message / Friend / etc.
	# We slot it in just above the close button so it's the first vertical option.
	var action_column: VBoxContainer = $PanelContainer/HBoxContainer/VBoxContainer
	_edit_button = Button.new()
	_edit_button.text = "Edit"
	_edit_button.pressed.connect(_open_edit_panel)
	action_column.add_child(_edit_button)
	action_column.move_child(_edit_button, 0)

	# Full-rect CenterContainer overlay so the edit panel is centered on the
	# profile no matter how the profile is laid out. The container blocks input
	# under the panel, giving a modal feel.
	var overlay: CenterContainer = CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.hide()
	add_child(overlay)

	_edit_panel = PanelContainer.new()
	_edit_panel.custom_minimum_size = Vector2(360, 420)
	_edit_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(_edit_panel)
	# Store the overlay on the panel so show/hide toggles both together.
	_edit_panel.set_meta(&"overlay", overlay)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 16)
	margin.add_theme_constant_override(&"margin_right", 16)
	margin.add_theme_constant_override(&"margin_top", 16)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	_edit_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 10)
	margin.add_child(vbox)

	var header: Label = Label.new()
	header.text = "Edit Profile"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	vbox.add_child(_make_field_label("Title"))
	_title_option = OptionButton.new()
	vbox.add_child(_title_option)

	vbox.add_child(_make_field_label("Animation"))
	_animation_option = OptionButton.new()
	vbox.add_child(_animation_option)

	vbox.add_child(_make_field_label("Status"))
	_status_edit = TextEdit.new()
	_status_edit.custom_minimum_size = Vector2(0, 80)
	_status_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_status_edit.text_changed.connect(_on_status_text_changed)
	vbox.add_child(_status_edit)

	_status_counter = Label.new()
	_status_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_status_counter)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override(&"separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	var cancel_button: Button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_close_edit_panel)
	button_row.add_child(cancel_button)

	var save_button: Button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)


func _make_field_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label


## Seed the form from the current profile payload and reveal the panel.
func _open_edit_panel() -> void:
	if _current_profile.is_empty():
		return

	# Title options: "(none)" + every unlocked title. Pre-select the active one.
	_title_option.clear()
	_title_option.add_item("(none)", 0)
	var titles: Array = _current_profile.get("titles_unlocked", [])
	var current_title: String = str(_current_profile.get("title", ""))
	var selected_idx: int = 0
	for i in titles.size():
		var t: String = str(titles[i])
		_title_option.add_item(t, i + 1)
		if t == current_title:
			selected_idx = i + 1
	_title_option.select(selected_idx)

	# Animations come from the server-side allowlist so client + server agree.
	_animation_option.clear()
	var animations: Array = _current_profile.get("allowed_animations", [])
	if animations.is_empty():
		animations = PlayerResource.ALLOWED_PROFILE_ANIMATIONS
	var current_animation: String = str(_current_profile.get("animation", "idle"))
	for i in animations.size():
		var a: String = str(animations[i])
		_animation_option.add_item(a, i)
		if a == current_animation:
			_animation_option.select(i)

	_status_edit.text = str(_current_profile.get("description", ""))
	_refresh_status_counter()
	_edit_panel.get_meta(&"overlay").show()


func _close_edit_panel() -> void:
	_edit_panel.get_meta(&"overlay").hide()


func _on_status_text_changed() -> void:
	var cap: int = int(_current_profile.get("max_status_len", PlayerResource.MAX_PROFILE_STATUS_LEN))
	if _status_edit.text.length() > cap:
		# Trim live so the player can't overrun the cap.
		var caret: int = _status_edit.get_caret_column()
		_status_edit.text = _status_edit.text.substr(0, cap)
		_status_edit.set_caret_column(mini(caret, cap))
	_refresh_status_counter()


func _refresh_status_counter() -> void:
	var cap: int = int(_current_profile.get("max_status_len", PlayerResource.MAX_PROFILE_STATUS_LEN))
	_status_counter.text = "%d / %d" % [_status_edit.text.length(), cap]


func _on_save_pressed() -> void:
	var selected_title: String = ""
	if _title_option.selected > 0:
		selected_title = _title_option.get_item_text(_title_option.selected)

	var animation: String = "idle"
	if _animation_option.selected >= 0:
		animation = _animation_option.get_item_text(_animation_option.selected)

	var payload: Dictionary = {
		"display_title": selected_title,
		"profile_status": _status_edit.text,
		"profile_animation": animation,
	}

	Client.request_data(
		&"profile.update",
		_on_profile_updated,
		payload,
		InstanceClient.current.name
	)


func _on_profile_updated(result: Dictionary) -> void:
	if not result.get("ok", false):
		return
	_close_edit_panel()
	# Re-fetch so the visible profile reflects the saved fields. Cheap, and
	# guarantees we render the same shape the server just committed.
	open_player_profile(int(_current_profile.get("id", 0)))
