extends Control
## Player profile panel. Master-detail layout: stats on the left, character +
## identity in the middle, description + earned-title strip on the right, action
## bar across the bottom. Self-profile gets an Edit pencil and the "More"
## overflow exposes future actions (report, block) for non-self.

const MORE_ITEM_EDIT: int = 0
const MORE_ITEM_REPORT: int = 1
const MORE_ITEM_BLOCK: int = 2
const MORE_ITEM_SHOW_GUILD: int = 3

# Stat-value colors so the eye can read kinds at a glance — gold = wealth,
# cyan = progression (level/hours), red = combat record.
const COLOR_VALUE_PROGRESS: Color = Color(0.55, 0.85, 0.95)
const COLOR_VALUE_GOLD: Color = Color(1.0, 0.85, 0.45)
const COLOR_VALUE_COMBAT: Color = Color(0.9, 0.4, 0.4)
const COLOR_VALUE_NEUTRAL: Color = Color(0.85, 0.85, 0.9)
const COLOR_DIM: Color = Color(0.7, 0.7, 0.75)
const COLOR_GUILD: Color = Color(0.55, 0.85, 0.95)

var cache: Dictionary[int, Dictionary]
## Most recent profile payload — used by the Edit panel to pre-seed fields.
var _current_profile: Dictionary

@onready var name_label: Label = %NameLabel
@onready var guild_label: Label = %GuildLabel
@onready var title_label: Label = %TitleLabel
@onready var account_label: Label = %AccountLabel
@onready var description_scroll: ScrollContainer = $CenterContainer/Card/CardMargin/VBox/Body/RightPanel/RightMargin/RightVBox/DescriptionScroll
@onready var description_text: RichTextLabel = %DescriptionText
@onready var stats_list: VBoxContainer = %StatsList
@onready var title_strip: HFlowContainer = %TitleStrip
@onready var player_character: AnimatedSprite2D = %PlayerCharacter

@onready var message_button: Button = %MessageButton
@onready var friend_button: Button = %FriendButton
@onready var invite_guild_button: Button = %InviteGuildButton
@onready var more_button: Button = %MoreButton
@onready var more_popup: PopupMenu = %MorePopup

# Built lazily — see _build_edit_ui at the bottom.
var _edit_panel: PanelContainer
var _title_option: OptionButton
var _animation_option: OptionButton
var _status_edit: TextEdit
var _status_counter: Label
var _trophies_container: VBoxContainer
var _trophies_counter: Label
## CheckBox-per-title built per open. Used to enforce the max-3 cap and to
## collect the selected set on save.
var _trophy_checkboxes: Array[CheckBox]


func _ready() -> void:
	more_button.pressed.connect(_show_more_popup)
	more_popup.id_pressed.connect(_on_more_item_pressed)
	DragScroll.enable(description_scroll) # touch/mouse drag-to-scroll the details column


func open_player_profile(player_id: int) -> void:
	Client.request_data(
		&"profile.get",
		apply_profile,
		{"id": player_id},
		InstanceClient.current.name
	)


## Open by the target's PEER id (a world click) — the server resolves peer -> player_id.
func open_player_profile_by_peer(peer_id: int) -> void:
	Client.request_data(
		&"profile.get",
		apply_profile,
		{"peer": peer_id},
		InstanceClient.current.name
	)


## Apply a profile payload to the panel: identity strip, sprite, stats column,
## description, earned-title strip, action-bar buttons.
func apply_profile(profile: Dictionary) -> void:
	_current_profile = profile

	var is_self: bool = profile.get("self", false)

	# Identity strip under the sprite. NameRow shows "Name (Guild)" so the
	# guild affiliation reads alongside the character name — first thing you
	# see. The guild fragment is its own Label so we can tint it cyan without
	# bbcode. Staff-only "#id" gets appended to the name for mods.
	var display_name: String = str(profile.get("name", "No Name"))
	if profile.get("staff_view", false):
		display_name += "  #%d" % int(profile.get("id", 0))
	name_label.text = display_name

	var guild_name: String = str(profile.get("guild_name", ""))
	guild_label.text = "(%s)" % guild_name if not guild_name.is_empty() else ""
	guild_label.visible = not guild_name.is_empty()

	var title: String = str(profile.get("title", ""))
	title_label.text = "— %s —" % title if not title.is_empty() else ""
	title_label.visible = not title.is_empty()

	# Account handle stays as the dim line under the title — it's secondary
	# identity info ("oh, that's their main account").
	var account_name: String = str(profile.get("account_name", ""))
	account_label.text = "@%s" % account_name if not account_name.is_empty() else ""
	account_label.visible = not account_name.is_empty()

	# Sprite + idle anim.
	set_player_character(
		int(profile.get("skin_id", 1)),
		str(profile.get("animation", "idle"))
	)

	# Bio panel. RichTextLabel so authors can BBCode if we want later.
	var description: String = str(profile.get("description", ""))
	description_text.clear()
	description_text.append_text(description)

	_render_stats(profile.get("stats", {}))
	_render_title_strip(profile)
	_render_action_bar(profile, is_self)

	if profile.get("id", 0):
		cache[profile.get("id")] = profile

	# Edit lives in the More popup now (self only). Build the modal lazily.
	if _edit_panel == null:
		_build_edit_ui()
	if _edit_panel.get_meta(&"overlay").visible:
		# Stale profile.get came in while editing — close the panel to avoid
		# overwriting the user's in-flight edits.
		_edit_panel.get_meta(&"overlay").hide()

	show()


# ---------------------------------------------------------------------------
# Left column — stats list
# ---------------------------------------------------------------------------

func _render_stats(stats: Dictionary) -> void:
	for child in stats_list.get_children():
		child.queue_free()

	# Hours: only show once the player has banked at least one full hour.
	# Below an hour just reads as "0h" which feels like a bug.
	var hours: int = int(stats.get("hours", 0))
	if hours > 0:
		stats_list.add_child(_stat_row("Hours", "%dh" % hours, COLOR_VALUE_NEUTRAL))

	# Level with a (MAX) badge at cap so capped players advertise it.
	var level: int = int(stats.get("level", 1))
	var level_text: String = "%d (MAX)" % level if level >= 20 else str(level)
	stats_list.add_child(_stat_row("Level", level_text, COLOR_VALUE_PROGRESS))

	stats_list.add_child(_stat_row("Gold", str(stats.get("money", 0)), COLOR_VALUE_GOLD))

	# PvE / PvP / Arena rendered as separate rows for clarity per design call.
	# Combat stats share the red palette so they read as a single category.
	stats_list.add_child(_stat_row("PvE kills", str(stats.get("pve_kills", 0)), COLOR_VALUE_COMBAT))
	stats_list.add_child(_stat_row("PvP kills", str(stats.get("pvp_kills", 0)), COLOR_VALUE_COMBAT))
	var wins: int = int(stats.get("arena_wins", 0))
	var losses: int = int(stats.get("arena_losses", 0))
	stats_list.add_child(_stat_row("Arena", "%d W / %d L" % [wins, losses], COLOR_VALUE_COMBAT))


## Two-column "Label: Value" row. Label is left-aligned, value right-aligned
## with a category-specific accent color so the eye groups kinds.
func _stat_row(label_text: String, value_text: String, value_color: Color) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)

	var label: Label = Label.new()
	label.text = "%s:" % label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value: Label = Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.self_modulate = value_color
	row.add_child(value)

	return row


# ---------------------------------------------------------------------------
# Right column — earned-title strip
# ---------------------------------------------------------------------------

func _render_title_strip(profile: Dictionary) -> void:
	for child in title_strip.get_children():
		child.queue_free()

	# displayed_trophies is the player's curated pick (up to 3). Shipped to
	# everyone — same view for self and others.
	var trophies: Array = profile.get("displayed_trophies", [])

	if trophies.is_empty():
		var empty: Label = Label.new()
		empty.text = "No trophies yet." if not profile.get("self", false) else "Pin trophies from Edit → Trophies."
		empty.self_modulate = Color(0.55, 0.55, 0.6)
		title_strip.add_child(empty)
		return

	for entry: Variant in trophies:
		title_strip.add_child(_title_chip(str(entry)))


## Pill-shaped read-only chip for an earned title. Uses a Button purely for the
## built-in panel styling; it's disabled so it doesn't take focus.
func _title_chip(text: String) -> Button:
	var chip: Button = Button.new()
	chip.text = "🏆 %s" % text
	chip.disabled = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


# ---------------------------------------------------------------------------
# Action bar — friend / message / invite guild / more
# ---------------------------------------------------------------------------

func _render_action_bar(profile: Dictionary, is_self: bool) -> void:
	# Self-profile: only the More menu (which exposes Edit) matters; hide the
	# rest since you can't message/friend/invite yourself.
	message_button.visible = not is_self
	friend_button.visible = not is_self
	invite_guild_button.visible = profile.get("can_guild_invite", false)
	invite_guild_button.disabled = not profile.get("can_guild_invite", false)

	var is_friend: bool = profile.get("friend", false)
	friend_button.text = "Remove friend" if is_friend else "Add friend"
	# Reset the disabled state — a prior "Add friend" click disabled it, and
	# without this it stays disabled for every profile opened afterwards (the
	# "can't add anyone" bug).
	friend_button.disabled = false

	if not is_self:
		# Defensive reconnect with bind so the latest payload's ids are used.
		if friend_button.pressed.is_connected(_on_friend_button_pressed):
			friend_button.pressed.disconnect(_on_friend_button_pressed)
		friend_button.pressed.connect(
			_on_friend_button_pressed.bind(profile.get("id", 0)),
			CONNECT_ONE_SHOT
		)

		var target_id: int = int(profile.get("id", 0))
		if message_button.pressed.is_connected(_on_message_button_pressed):
			message_button.pressed.disconnect(_on_message_button_pressed)
		message_button.pressed.connect(
			_on_message_button_pressed.bind(target_id),
			CONNECT_ONE_SHOT
		)

		if invite_guild_button.pressed.is_connected(_on_invite_guild_button_pressed):
			invite_guild_button.pressed.disconnect(_on_invite_guild_button_pressed)
		
		if profile.get("can_guild_invite", false):
			invite_guild_button.pressed.connect(
				_on_invite_guild_button_pressed.bind(target_id),
				CONNECT_ONE_SHOT
			)


func _show_more_popup() -> void:
	more_popup.clear()
	var is_self: bool = _current_profile.get("self", false)
	if is_self:
		more_popup.add_item("Edit profile", MORE_ITEM_EDIT)
	else:
		more_popup.add_item("Report player", MORE_ITEM_REPORT)
		# Authoritative state comes from the profile payload (server checks
		# BlockList) but ClientState.blocked_ids may have updated since this
		# profile was fetched — prefer the live set.
		var target_id: int = int(_current_profile.get("id", 0))
		var is_blocked: bool = ClientState.blocked_ids.has(target_id) or bool(_current_profile.get("blocked", false))
		more_popup.add_item("Unblock player" if is_blocked else "Block player", MORE_ITEM_BLOCK)
		more_popup.set_item_disabled(more_popup.get_item_index(MORE_ITEM_REPORT), true)
	# "Show Guild" surfaces whenever the target has one (regardless of self).
	if not str(_current_profile.get("guild_name", "")).is_empty():
		more_popup.add_item("Show Guild", MORE_ITEM_SHOW_GUILD)
	# reset_size so the post-clear size reflects the actual item count, then
	# anchor the popup ABOVE the button (the action bar sits at the bottom of
	# the card — popping downward would clip off-screen).
	more_popup.reset_size()
	var popup_h: int = int(more_popup.size.y)
	var anchor_x: float = more_button.global_position.x + more_button.size.x - more_popup.size.x
	var anchor_y: float = more_button.global_position.y - popup_h - 4.0
	more_popup.position = Vector2i(roundi(anchor_x), roundi(anchor_y))
	more_popup.popup()


func _on_more_item_pressed(id: int) -> void:
	match id:
		MORE_ITEM_EDIT:
			_open_edit_panel()
		MORE_ITEM_BLOCK:
			_on_block_toggle_pressed()
		MORE_ITEM_SHOW_GUILD:
			# Route to the guild panel via the same open_menu_requested signal
			# the rest of the world uses. Guild id isn't currently shipped on
			# the profile payload — emit by name and let the guild menu resolve
			# the active guild for the target if a future change adds it.
			ClientState.open_menu_requested.emit(&"guild", str(_current_profile.get("guild_name", "")))
			hide()
		# REPORT is deliberately a disabled stub for now.


func _on_block_toggle_pressed() -> void:
	var target_id: int = int(_current_profile.get("id", 0))
	if target_id <= 0:
		return
	var target_name: String = str(_current_profile.get("name", ""))
	var is_blocked: bool = ClientState.blocked_ids.has(target_id)

	if is_blocked:
		Client.request_data(
			&"social.block.remove",
			_on_block_changed.bind(false, target_id, target_name),
			{"id": target_id},
			InstanceClient.current.name
		)
	else:
		Client.request_data(
			&"social.block.add",
			_on_block_changed.bind(true, target_id, target_name),
			{"id": target_id},
			InstanceClient.current.name
		)


func _on_block_changed(result: Dictionary, expected_blocked: bool, target_id: int, target_name: String) -> void:
	if not result.get("ok", false):
		Toaster.toast(str(result.get("msg", "Action failed.")))
		return

	if expected_blocked:
		ClientState.add_blocked(target_id)
		Toaster.toast("Blocked %s." % target_name)
	else:
		ClientState.remove_blocked(target_id)
		Toaster.toast("Unblocked %s." % target_name)

	_current_profile["blocked"] = expected_blocked
	hide()


# ---------------------------------------------------------------------------
# Character preview (skin + animation)
# ---------------------------------------------------------------------------

func set_player_character(skin_id: int, animation: String) -> void:
	var skin: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", skin_id)
	if not skin:
		return
	player_character.stop()
	player_character.sprite_frames = skin
	if player_character.sprite_frames.has_animation(animation):
		player_character.play(animation)


# ---------------------------------------------------------------------------
# Buttons / friend + message handlers
# ---------------------------------------------------------------------------

func _on_close_pressed() -> void:
	hide()


func _on_friend_button_pressed(player_id: int) -> void:
	# "Remove friend" actually removes now (was always sending an add request).
	var is_friend: bool = bool(_current_profile.get("friend", false))
	var topic: StringName = &"friend.remove" if is_friend else &"friend.request"
	Client.request_data(topic, func(data: Dictionary) -> void:
		Toaster.toast(str(data.get("msg", "Done."))),
		{"id": player_id})
	_current_profile["friend"] = not is_friend
	friend_button.disabled = true
	friend_button.text = "Removed" if is_friend else "Added"


func _on_invite_guild_button_pressed(player_id: int) -> void:
	Client.request_data(&"guild.invite", Callable(), {"id": player_id})
	invite_guild_button.disabled = true
	invite_guild_button.text = "Invited"


func _on_message_button_pressed(target_id: int) -> void:
	ClientState.dm_requested.emit(target_id)
	hide()


# ---------------------------------------------------------------------------
# Self-profile Edit modal (title selector + status + animation). Programmatic
# build so the scene file stays lean and survives layout reorganization.
# ---------------------------------------------------------------------------

func _build_edit_ui() -> void:
	var overlay: MarginContainer = MarginContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	for side: String in ["left", "right", "top", "bottom"]:
		overlay.add_theme_constant_override("margin_" + side, 20)
	overlay.hide()
	add_child(overlay)

	_edit_panel = PanelContainer.new()
	_edit_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(_edit_panel)
	_edit_panel.set_meta(&"overlay", overlay)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_edit_panel.add_child(margin)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override(&"separation", 10)
	scroll.add_child(vbox)

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
	_status_edit.custom_minimum_size = Vector2(0, 90)
	_status_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_status_edit.text_changed.connect(_on_status_text_changed)
	vbox.add_child(_status_edit)

	_status_counter = Label.new()
	_status_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_status_counter)

	# Trophy picker: a scroll of checkboxes (one per unlocked title), max 3
	# checked at once. Header + live counter so the cap is obvious.
	var trophy_header: HBoxContainer = HBoxContainer.new()
	vbox.add_child(trophy_header)
	var trophy_label: Label = _make_field_label("Trophies")
	trophy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trophy_header.add_child(trophy_label)
	_trophies_counter = Label.new()
	_trophies_counter.text = "0 / %d" % PlayerResource.MAX_DISPLAYED_TROPHIES
	_trophies_counter.self_modulate = COLOR_DIM
	trophy_header.add_child(_trophies_counter)

	_trophies_container = VBoxContainer.new()
	_trophies_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trophies_container.add_theme_constant_override(&"separation", 2)
	vbox.add_child(_trophies_container)

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


func _open_edit_panel() -> void:
	if _current_profile.is_empty():
		return
	if _edit_panel == null:
		_build_edit_ui()

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

	# Trophy checkboxes: one per unlocked title, pre-checked for current picks.
	for child in _trophies_container.get_children():
		child.queue_free()
	_trophy_checkboxes.clear()
	var current_trophies: Array = _current_profile.get("displayed_trophies", [])
	for unlocked_title: Variant in titles:
		var box: CheckBox = CheckBox.new()
		box.text = str(unlocked_title)
		box.button_pressed = current_trophies.has(unlocked_title)
		box.toggled.connect(_on_trophy_toggled)
		_trophies_container.add_child(box)
		_trophy_checkboxes.append(box)
	_refresh_trophy_state()

	_edit_panel.get_meta(&"overlay").show()


func _close_edit_panel() -> void:
	_edit_panel.get_meta(&"overlay").hide()


func _on_status_text_changed() -> void:
	var cap: int = int(_current_profile.get("max_status_len", PlayerResource.MAX_PROFILE_STATUS_LEN))
	if _status_edit.text.length() > cap:
		var caret: int = _status_edit.get_caret_column()
		_status_edit.text = _status_edit.text.substr(0, cap)
		_status_edit.set_caret_column(mini(caret, cap))
	_refresh_status_counter()


func _refresh_status_counter() -> void:
	var cap: int = int(_current_profile.get("max_status_len", PlayerResource.MAX_PROFILE_STATUS_LEN))
	_status_counter.text = "%d / %d" % [_status_edit.text.length(), cap]


## Live trophy-cap enforcement: when 3 are checked, all unchecked boxes go
## disabled so the player can't pick a 4th. Counter mirrors the live count.
func _on_trophy_toggled(_pressed: bool) -> void:
	_refresh_trophy_state()


func _refresh_trophy_state() -> void:
	var cap: int = int(_current_profile.get("max_displayed_trophies", PlayerResource.MAX_DISPLAYED_TROPHIES))
	var checked: int = 0
	for box: CheckBox in _trophy_checkboxes:
		if box.button_pressed:
			checked += 1
	_trophies_counter.text = "%d / %d" % [checked, cap]
	# Disable unchecked boxes only when we hit the cap.
	for box: CheckBox in _trophy_checkboxes:
		box.disabled = checked >= cap and not box.button_pressed


func _on_save_pressed() -> void:
	var selected_title: String = ""
	if _title_option.selected > 0:
		selected_title = _title_option.get_item_text(_title_option.selected)

	var animation: String = "idle"
	if _animation_option.selected >= 0:
		animation = _animation_option.get_item_text(_animation_option.selected)

	var selected_trophies: Array = []
	for box: CheckBox in _trophy_checkboxes:
		if box.button_pressed:
			selected_trophies.append(box.text)

	var payload: Dictionary = {
		"display_title": selected_title,
		"profile_status": _status_edit.text,
		"profile_animation": animation,
		"displayed_trophies": selected_trophies,
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
	open_player_profile(int(_current_profile.get("id", 0)))
