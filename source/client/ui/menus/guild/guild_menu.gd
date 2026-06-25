extends MenuShell
## Guild menu (Phase 1) — MenuShell split view, replacing the old Navigator
## stack. Left: your joined guilds (★ = active/tagged) + Create + Browse.
## Right: the selected guild's detail with Profile / Members / Glory / Settings
## sub-views. Browse / view / create / leave / edit are wired here; tag, invite,
## kick and rank-change land in Phase 2 (see docs/guild.md).

const LOGOS: Array[Texture2D] = [
	preload("res://assets/sprites/guild_logos/wyvern.png"),
	preload("res://assets/sprites/guild_logos/kawaii_skull.png"),
	preload("res://assets/sprites/guild_logos/cute_crown.png"),
	preload("res://assets/sprites/guild_logos/cute_fish.png"),
]

const COLOR_GOLD: Color = Color(1.0, 0.95, 0.75)
const COLOR_SECTION: Color = Color(1.0, 0.85, 0.5)
const COLOR_MUTED: Color = Color(0.75, 0.77, 0.83)

var _left_list: VBoxContainer
var _right_host: VBoxContainer

var _joined: Array
## Name of the guild currently shown on the right ("" = none / a special view).
var _selected_name: String
var _section: String = "profile"
## Last guild.get payload for the selected guild.
var _guild: Dictionary
## Last guild.get.members payload (members + ranks + viewer) — drives the
## manage popup's gating + rank dropdown.
var _members_data: Dictionary
## True while showing a guild the viewer isn't in (opened via "Show Guild" on
## another player's profile). Stops _on_joined from snapping back to your guild.
var _external_view: bool = false


func _ready() -> void:
	build_shell("Guild", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	_refresh()


## Open to a specific guild by name (e.g. "Show Guild" from another player's
## profile — possibly a guild you're not in). Called by the HUD's display_menu
## with the Variant arg.
func open(arg: Variant) -> void:
	if arg is String and not (arg as String).is_empty():
		_external_view = true
		_select_guild(arg as String)


func _build_layout() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 12)
	content.add_child(hbox)

	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.65
	hbox.add_child(left_scroll)

	_left_list = VBoxContainer.new()
	_left_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_list.add_theme_constant_override(&"separation", 4)
	left_scroll.add_child(_left_list)

	_right_host = VBoxContainer.new()
	_right_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_host.size_flags_stretch_ratio = 1.6
	_right_host.add_theme_constant_override(&"separation", 8)
	hbox.add_child(_right_host)


# ---------------------------------------------------------------------------
# Left column — joined guilds + Create / Browse
# ---------------------------------------------------------------------------

func _refresh() -> void:
	Client.request_data(&"guild.get.joined_guilds", _on_joined, {}, _inst())


func _on_joined(data: Dictionary) -> void:
	_joined = data.get("guilds", [])
	_rebuild_left()
	# Viewing another player's guild (Show Guild): keep it shown, don't snap to
	# the default. One-shot — a later refresh returns to normal behavior.
	if _external_view:
		_external_view = false
		return
	if _selected_name == "" or not _is_joined(_selected_name):
		_selected_name = _default_guild_name()
	if _selected_name != "":
		_select_guild(_selected_name)
	else:
		_show_message("You're not in a guild yet.\nCreate one or browse to find others.")


func _rebuild_left() -> void:
	for child: Node in _left_list.get_children():
		child.queue_free()

	_left_list.add_child(_make_section_header("My Guilds"))
	if _joined.is_empty():
		var none: Label = Label.new()
		none.text = "None yet"
		none.modulate.a = 0.55
		_left_list.add_child(none)
	for g: Dictionary in _joined:
		var gname: String = str(g.get("name", "?"))
		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.button_pressed = (gname == _selected_name)
		btn.text = ("★ " if bool(g.get("is_active", false)) else "") + gname
		btn.pressed.connect(_select_guild.bind(gname))
		_left_list.add_child(btn)

	_left_list.add_child(HSeparator.new())
	_left_list.add_child(_make_left_action("+  Create guild", _show_create))
	_left_list.add_child(_make_left_action("🔍  Browse", _show_browse))

	# Touch/mouse drag-to-scroll for the joined-guilds list.
	DragScroll.enable(_left_list.get_parent() as ScrollContainer)


func _make_left_action(text: String, on_pressed: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 38)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(on_pressed)
	return btn


func _select_guild(guild_name: String) -> void:
	_selected_name = guild_name
	_clear_left_selection()
	for child: Node in _left_list.get_children():
		if child is Button and (child as Button).toggle_mode:
			(child as Button).button_pressed = (child as Button).text.ends_with(guild_name)
	Client.request_data(&"guild.get", _on_guild_loaded, {"q": guild_name}, _inst())


func _clear_left_selection() -> void:
	for child: Node in _left_list.get_children():
		if child is Button and (child as Button).toggle_mode:
			(child as Button).button_pressed = false


func _on_guild_loaded(data: Dictionary) -> void:
	if not data.has("name"):
		_show_message("Guild not found.")
		return
	_guild = data
	_section = "profile"
	_rebuild_right()


# ---------------------------------------------------------------------------
# Right column — guild detail (header + section tabs + section content)
# ---------------------------------------------------------------------------

func _rebuild_right() -> void:
	for child: Node in _right_host.get_children():
		child.queue_free()

	var is_member: bool = bool(_guild.get("is_member", false))

	# --- Header: logo + name/leader + tag toggle ---
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	_right_host.add_child(header)

	var logo: TextureRect = TextureRect.new()
	logo.custom_minimum_size = Vector2(56, 56)
	logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture = _logo_for(int(_guild.get("logo_id", 0)))
	header.add_child(logo)

	var title_col: VBoxContainer = VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_col)

	var name_label: Label = Label.new()
	name_label.text = str(_guild.get("name", "?"))
	name_label.add_theme_font_size_override(&"font_size", 20)
	name_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	title_col.add_child(name_label)

	var sub: Label = Label.new()
	sub.text = "Leader: %s   ·   %d / %d members" % [
		str(_guild.get("leader_name", "?")),
		int(_guild.get("size", 0)),
		int(_guild.get("max_members", Guild.MAX_MEMBERS)),
	]
	sub.add_theme_color_override(&"font_color", COLOR_MUTED)
	sub.add_theme_font_size_override(&"font_size", 12)
	title_col.add_child(sub)

	if is_member:
		var tag_button: Button = Button.new()
		tag_button.text = "Untag" if bool(_guild.get("is_active", false)) else "Tag"
		tag_button.custom_minimum_size = Vector2(90, 36)
		tag_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag_button.tooltip_text = "Set this as your active guild (safe zone only)."
		tag_button.pressed.connect(_on_tag_pressed)
		header.add_child(tag_button)

	_right_host.add_child(HSeparator.new())

	# --- Section tabs. "Settings" is a sub-view of the "More" hub (which also
	# holds future features), so the More tab stays highlighted while it shows. ---
	var sections: Array = [["profile", "Profile"], ["members", "Members"]]
	if is_member:
		sections.append(["more", "More"])
	# "settings" is a sub-view of the More hub — keep More highlighted while on it.
	# (Guild Hall is a modal overlay, not a section.)
	if _section != "settings" and not _section_exists(sections, _section):
		_section = "profile"
	var active_tab: String = "more" if _section == "settings" else _section

	var section_bar: HBoxContainer = HBoxContainer.new()
	section_bar.add_theme_constant_override(&"separation", 4)
	_right_host.add_child(section_bar)
	for s: Array in sections:
		var btn: Button = Button.new()
		btn.text = s[1]
		btn.theme_type_variation = &"SectionTab"
		btn.toggle_mode = true
		btn.button_pressed = (s[0] == active_tab)
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_section.bind(str(s[0])))
		section_bar.add_child(btn)

	# --- Section content ---
	var area: PanelContainer = PanelContainer.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_host.add_child(area)

	match _section:
		"members":
			_view_members(area)
		"more":
			_view_more(area)
		"settings":
			_view_settings(area)
		_:
			_view_profile(area)


func _select_section(section: String) -> void:
	_section = section
	_rebuild_right()


## Tag / untag the selected guild. The server gates it (safe zone + cooldown);
## on failure we surface the reason. A refresh updates the ★ marker + button.
func _on_tag_pressed() -> void:
	Client.request_data(&"guild.tag", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't change tag.")))
		_refresh(),
		{"guild_name": _selected_name}, _inst())


# --- Sections ---

func _view_profile(parent: Node) -> void:
	var box: VBoxContainer = _padded(parent)

	# Top: big logo on the left, description on the right.
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 16)
	box.add_child(top)

	var big_logo: TextureRect = TextureRect.new()
	# EXPAND_IGNORE_SIZE pins the node to custom_minimum_size no matter how tall
	# the row gets — a long description must never inflate the logo. SHRINK_CENTER
	# keeps the HBox from stretching it vertically.
	big_logo.custom_minimum_size = Vector2(120, 120)
	big_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	big_logo.texture = _logo_for(int(_guild.get("logo_id", 0)))
	top.add_child(big_logo)

	var desc: String = str(_guild.get("description", ""))
	# RichTextLabel with fit_content OFF: fixed-height box (matches the logo) that
	# scrolls internally when the text overflows — the row's size is CONSTANT
	# regardless of description length. Also immune to the autowrap-Label-in-HBox
	# min-size oscillation that used to hard-crash this view. bbcode stays OFF —
	# descriptions are player-written, no tag injection.
	var desc_label: RichTextLabel = RichTextLabel.new()
	desc_label.bbcode_enabled = true
	desc_label.fit_content = false
	desc_label.scroll_active = true
	desc_label.custom_minimum_size = Vector2(0, 120)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	desc_label.text = desc if not desc.is_empty() else "No description."
	desc_label.add_theme_color_override(&"default_color", COLOR_MUTED)
	top.add_child(desc_label)

	box.add_child(HSeparator.new())

	# Stats (members is on the header bar, so it's omitted here).
	box.add_child(_make_section_header("Stats"))
	box.add_child(_stat_row("Kills", int(_guild.get("total_kills", 0))))
	box.add_child(_stat_row_str("Base time", _format_duration(int(_guild.get("territory_seconds", 0)))))
	box.add_child(_stat_row("Seasonal glory", int(_guild.get("seasonal_glory", 0))))
	box.add_child(_stat_row("Eternal glory", int(_guild.get("eternal_glory", 0))))
	box.add_child(_stat_row("Spar score", int(_guild.get("spar_score", 0))))

	box.add_child(_make_section_header("Trophies"))
	var trophies: Label = Label.new()
	trophies.text = "No trophies yet — earn them through guild feats. (coming soon)"
	trophies.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trophies.add_theme_color_override(&"font_color", COLOR_MUTED)
	trophies.add_theme_font_size_override(&"font_size", 12)
	box.add_child(trophies)


func _view_members(parent: Node) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override(&"separation", 4)
	scroll.add_child(vbox)
	Client.request_data(&"guild.get.members", func(data: Dictionary) -> void:
		_fill_members(vbox, data), {"q": _selected_name}, _inst())


func _fill_members(vbox: VBoxContainer, data: Dictionary) -> void:
	if not is_instance_valid(vbox):
		return
	_members_data = data
	for child: Node in vbox.get_children():
		child.queue_free()
	for member: Dictionary in data.get("members", []):
		# Whole row is clickable. If the viewer can manage this member it opens
		# the manage popup (rank / kick); otherwise it opens their profile.
		var row: Button = Button.new()
		row.custom_minimum_size = Vector2(0, 44)
		row.pressed.connect(_on_member_clicked.bind(member))

		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.offset_left = 8
		hbox.offset_right = -8
		hbox.add_theme_constant_override(&"separation", 8)
		row.add_child(hbox)

		var rank_label: Label = Label.new()
		rank_label.text = str(member.get("rank_name", "Member"))
		rank_label.custom_minimum_size = Vector2(72, 0)
		rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank_label.add_theme_color_override(&"font_color", COLOR_SECTION)
		rank_label.add_theme_font_size_override(&"font_size", 12)
		hbox.add_child(rank_label)

		var name_label: Label = Label.new()
		name_label.text = str(member.get("name", "?"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(name_label)

		vbox.add_child(row)

	# Touch/mouse drag-to-scroll for the member roster.
	DragScroll.enable(vbox.get_parent() as ScrollContainer)


func _on_member_clicked(member: Dictionary) -> void:
	if _can_manage(member):
		_open_member_popup(member)
	else:
		ClientState.player_profile_requested.emit(int(member.get("id", 0)))


## Client mirror of Guild.can_act + permission check: can the viewer manage
## (rank/kick) this member?
func _can_manage(member: Dictionary) -> bool:
	var viewer: Dictionary = _members_data.get("viewer", {})
	var perms: int = int(viewer.get("permissions", 0))
	if (perms & Guild.Permissions.KICK) == 0 and (perms & Guild.Permissions.PROMOTE) == 0:
		return false
	var member_id: int = int(member.get("id", 0))
	if member_id == int(viewer.get("player_id", 0)):
		return false
	if member_id == int(_members_data.get("leader_id", 0)):
		return false
	if bool(viewer.get("is_leader", false)):
		return true
	return int(viewer.get("grade", 100)) < int(member.get("grade", 100))


## Modal manage popup for one member: View Profile + (rank dropdown) + (Kick),
## each gated by the viewer's permissions.
func _open_member_popup(member: Dictionary) -> void:
	var member_id: int = int(member.get("id", 0))
	var viewer: Dictionary = _members_data.get("viewer", {})
	var perms: int = int(viewer.get("permissions", 0))
	var can_kick: bool = (perms & Guild.Permissions.KICK) != 0
	var can_rank: bool = (perms & Guild.Permissions.PROMOTE) != 0

	var overlay: Control = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.6)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			overlay.queue_free())
	overlay.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(480, 0)
	center.add_child(card)
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	pad.add_child(box)

	var name_label: Label = Label.new()
	name_label.text = str(member.get("name", "?"))
	name_label.add_theme_font_size_override(&"font_size", 18)
	name_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	box.add_child(name_label)

	var rank_label: Label = Label.new()
	rank_label.text = "Rank: %s" % str(member.get("rank_name", "Member"))
	rank_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	box.add_child(rank_label)
	box.add_child(HSeparator.new())

	# Two columns so the popup stays short enough to fit on screen: actions on
	# the left, individual permissions on the right.
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 16)
	box.add_child(cols)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 6)
	cols.add_child(left)

	var profile_btn: Button = Button.new()
	profile_btn.text = "View Profile"
	profile_btn.custom_minimum_size = Vector2(0, 36)
	profile_btn.pressed.connect(func() -> void:
		ClientState.player_profile_requested.emit(member_id))
	left.add_child(profile_btn)

	if can_rank:
		left.add_child(_make_section_header("Change rank"))
		var picker: OptionButton = OptionButton.new()
		var allowed: Array = _assignable_ranks(viewer)
		var current_rank_id: int = int(member.get("rank_id", -1))
		for r: Dictionary in allowed:
			picker.add_item(str(r.get("name", "?")), int(r.get("id", 0)))
			if int(r.get("id", -2)) == current_rank_id:
				picker.select(picker.item_count - 1)
		left.add_child(picker)
		var apply: Button = Button.new()
		apply.text = "Apply rank"
		apply.custom_minimum_size = Vector2(0, 36)
		apply.disabled = picker.item_count == 0
		apply.pressed.connect(func() -> void:
			if picker.item_count == 0:
				return
			overlay.queue_free()
			_change_rank(member_id, picker.get_selected_id()))
		left.add_child(apply)

	# Right column: individual permission overrides (R5 / leader only).
	if bool(viewer.get("is_leader", false)) or int(viewer.get("grade", 100)) == 0:
		var right: VBoxContainer = VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override(&"separation", 4)
		cols.add_child(right)
		right.add_child(_make_section_header("Permissions"))
		var current_perms: int = int(member.get("perms", 0))
		var perm_defs: Array = [
			[Guild.Permissions.INVITE, "Recruit (invite)"],
			[Guild.Permissions.KICK, "Kick members"],
			[Guild.Permissions.PROMOTE, "Manage ranks"],
			[Guild.Permissions.EDIT, "Edit guild"],
		]
		var checks: Array[CheckBox] = []
		for pd: Array in perm_defs:
			var cb: CheckBox = CheckBox.new()
			cb.text = str(pd[1])
			cb.button_pressed = (current_perms & int(pd[0])) != 0
			cb.set_meta(&"flag", int(pd[0]))
			right.add_child(cb)
			checks.append(cb)
		var save_perms: Button = Button.new()
		save_perms.text = "Save permissions"
		save_perms.custom_minimum_size = Vector2(0, 36)
		save_perms.pressed.connect(func() -> void:
			var mask: int = 0
			for c: CheckBox in checks:
				if c.button_pressed:
					mask |= int(c.get_meta(&"flag"))
			overlay.queue_free()
			_set_member_perms(member_id, mask))
		right.add_child(save_perms)

	# Bottom bar: Kick + Close span the width.
	box.add_child(HSeparator.new())
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 8)
	box.add_child(bottom)
	if can_kick:
		var kick: Button = Button.new()
		kick.text = "Kick from guild"
		kick.custom_minimum_size = Vector2(0, 36)
		kick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kick.add_theme_color_override(&"font_color", Color(0.95, 0.6, 0.55))
		kick.pressed.connect(func() -> void:
			overlay.queue_free()
			_kick_member(member_id))
		bottom.add_child(kick)
	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(overlay.queue_free)
	bottom.add_child(close_btn)


## Ranks the viewer may assign: all if leader, else only ranks strictly below
## their own authority (higher grade).
func _assignable_ranks(viewer: Dictionary) -> Array:
	var ranks: Array = _members_data.get("ranks", [])
	if bool(viewer.get("is_leader", false)):
		return ranks
	var out: Array = []
	var viewer_grade: int = int(viewer.get("grade", 100))
	for r: Dictionary in ranks:
		if int(r.get("grade", 100)) > viewer_grade:
			out.append(r)
	return out


func _change_rank(target_id: int, rank_id: int) -> void:
	Client.request_data(&"guild.rank", func(_d: Dictionary) -> void:
		_refresh_current(),
		{"guild_name": _selected_name, "target_id": target_id, "rank_id": rank_id}, _inst())


func _kick_member(target_id: int) -> void:
	Client.request_data(&"guild.kick", func(_d: Dictionary) -> void:
		_refresh_current(),
		{"guild_name": _selected_name, "target_id": target_id}, _inst())


func _set_member_perms(target_id: int, permissions: int) -> void:
	Client.request_data(&"guild.perms", func(_d: Dictionary) -> void:
		_refresh_current(),
		{"guild_name": _selected_name, "target_id": target_id, "permissions": permissions}, _inst())


## Re-fetches the current guild (updates size/glory) and rebuilds the right
## column WITHOUT resetting the active section (so you stay on Members after a
## kick/rank change).
func _refresh_current() -> void:
	if _selected_name == "":
		return
	Client.request_data(&"guild.get", func(data: Dictionary) -> void:
		if data.has("name"):
			_guild = data
			_rebuild_right(),
		{"q": _selected_name}, _inst())


## The "More" hub — Settings plus space for future guild features. Settings is
## live; the rest are placeholders that signal the roadmap (see docs/guild.md).
func _view_more(parent: Node) -> void:
	var box: VBoxContainer = _padded(parent)
	box.add_child(_more_entry("🏛  Guild Hall", true, func() -> void: _open_hall_panel()))
	box.add_child(_more_entry("⚙  Settings", true, func() -> void: _select_section("settings")))
	box.add_child(_more_entry("🏆  Trophies", false, Callable()))
	box.add_child(_more_entry("🤝  Allies", false, Callable()))
	box.add_child(_more_entry("🏝  Island", false, Callable()))

	box.add_child(HSeparator.new())
	if bool(_guild.get("is_leader", false)):
		var leader_note: Label = Label.new()
		leader_note.text = "As the leader, you can't leave (disband/transfer comes later)."
		leader_note.modulate.a = 0.55
		leader_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		leader_note.add_theme_font_size_override(&"font_size", 12)
		box.add_child(leader_note)
	else:
		var leave: Button = Button.new()
		leave.text = "🚪  Leave guild"
		leave.alignment = HORIZONTAL_ALIGNMENT_LEFT
		leave.custom_minimum_size = Vector2(0, 42)
		leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leave.add_theme_color_override(&"font_color", Color(0.95, 0.6, 0.55))
		leave.pressed.connect(_leave_guild)
		box.add_child(leave)


func _more_entry(text: String, enabled: bool, on_pressed: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text if enabled else text + "    (soon)"
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 42)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not enabled
	if enabled and on_pressed.is_valid():
		btn.pressed.connect(on_pressed)
	return btn


# Live references into the open Guild Hall modal, so a buy/deposit updates these
# widgets IN PLACE instead of closing + reopening the modal (which flickered and
# reset the scroll position).
var _hall_balance_label: Label
var _hall_caps_label: Label
var _hall_gold_label: Label
var _hall_deposit_spin: SpinBox
var _hall_rows: Dictionary # upgrade id (String) -> {"title": Label, "buy": Button}


## Opens the Guild Hall as a focused modal (like the member popup) so treasury,
## deposit, and the upgrade list have room instead of cramping the side panel.
## Buy/deposit refresh the widgets in place (see _refresh_hall_in_place).
func _open_hall_panel() -> void:
	var overlay: Control = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.6)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			overlay.queue_free())
	overlay.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(660, 0)
	center.add_child(card)
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	card.add_child(pad)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	pad.add_child(box)

	# Header: title + Close.
	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)
	var title: Label = Label.new()
	title.text = "🏛  Guild Hall"
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", COLOR_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: overlay.queue_free())
	header.add_child(close)
	box.add_child(HSeparator.new())

	# Two columns so the panel stays short in Y: left treasury/deposit, right upgrades.
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 18)
	box.add_child(cols)

	# --- Left: treasury + deposit ---
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override(&"separation", 6)
	cols.add_child(left)

	left.add_child(_make_section_header("Treasury"))
	var balance: Label = Label.new()
	balance.text = "%d  Guild Funds" % int(_guild.get("treasury", 0))
	balance.add_theme_font_size_override(&"font_size", 22)
	balance.add_theme_color_override(&"font_color", COLOR_GOLD)
	left.add_child(balance)
	_hall_balance_label = balance

	var caps: Label = Label.new()
	caps.text = "Tag cap: %d online\nRoster: %d / %d" % [
		int(_guild.get("tag_cap", 15)), int(_guild.get("size", 0)), int(_guild.get("max_members", 25))]
	caps.add_theme_color_override(&"font_color", COLOR_MUTED)
	caps.add_theme_font_size_override(&"font_size", 12)
	left.add_child(caps)
	_hall_caps_label = caps

	left.add_child(HSeparator.new())
	left.add_child(_make_section_header("Deposit gold"))
	var gold: int = int(_guild.get("viewer_gold", 0))
	var gold_label: Label = Label.new()
	gold_label.text = "You have %d gold" % gold
	gold_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	gold_label.add_theme_font_size_override(&"font_size", 12)
	left.add_child(gold_label)
	_hall_gold_label = gold_label

	var dep_row: HBoxContainer = HBoxContainer.new()
	dep_row.add_theme_constant_override(&"separation", 8)
	left.add_child(dep_row)
	var amount_field: SpinBox = SpinBox.new()
	amount_field.min_value = 0
	amount_field.max_value = maxi(gold, 0)
	amount_field.value = mini(100, gold)
	amount_field.step = 10
	amount_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dep_row.add_child(amount_field)
	_hall_deposit_spin = amount_field
	var deposit: Button = Button.new()
	deposit.text = "Deposit"
	deposit.disabled = gold <= 0
	deposit.pressed.connect(func() -> void:
		_deposit_treasury(int(amount_field.value)))
	dep_row.add_child(deposit)

	# --- Right: upgrades ---
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 6)
	cols.add_child(right)
	right.add_child(_make_section_header("Upgrades"))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 300)
	right.add_child(scroll)
	var ups_box: VBoxContainer = VBoxContainer.new()
	ups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ups_box.add_theme_constant_override(&"separation", 6)
	scroll.add_child(ups_box)

	var perms: int = int(_guild.get("permissions", 0))
	var can_upgrade: bool = (perms & Guild.Permissions.EDIT) != 0
	var treasury: int = int(_guild.get("treasury", 0))
	_hall_rows = {}
	for up: Dictionary in _guild.get("hall_upgrades", []):
		ups_box.add_child(_upgrade_row(up, can_upgrade, treasury))

	if not can_upgrade:
		var note: Label = Label.new()
		note.text = "Only members with the Edit permission can buy upgrades."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override(&"font_color", COLOR_MUTED)
		note.add_theme_font_size_override(&"font_size", 11)
		right.add_child(note)


## One Guild Hall upgrade row: name + level, description, and a Buy button
## (disabled if maxed, unaffordable, or the viewer lacks the Edit permission).
## Registers its title/buy into _hall_rows so it can be refreshed in place.
func _upgrade_row(up: Dictionary, can_upgrade: bool, treasury: int) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(pad)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	pad.add_child(row)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var title: Label = Label.new()
	title.add_theme_color_override(&"font_color", COLOR_GOLD)
	info.add_child(title)

	var desc: Label = Label.new()
	desc.text = str(up.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override(&"font_color", COLOR_MUTED)
	desc.add_theme_font_size_override(&"font_size", 11)
	info.add_child(desc)

	var uid: String = str(up.get("id", ""))
	var buy: Button = Button.new()
	buy.custom_minimum_size = Vector2(120, 36)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(func() -> void: _buy_upgrade(uid))
	row.add_child(buy)

	_hall_rows[uid] = {"title": title, "buy": buy}
	# Title + buy state are filled by the shared updater (also used on refresh).
	_update_upgrade_row(_hall_rows[uid], up, can_upgrade, treasury)
	return panel


## Set a row's title + buy-button state from an upgrade entry. Used both at build
## time and when refreshing the modal in place.
func _update_upgrade_row(refs: Dictionary, up: Dictionary, can_upgrade: bool, treasury: int) -> void:
	var title: Label = refs.get("title")
	var buy: Button = refs.get("buy")
	if is_instance_valid(title):
		title.text = "%s   (Lv %d / %d)" % [
			str(up.get("name", "?")), int(up.get("level", 0)), int(up.get("max_level", 0))]
	if not is_instance_valid(buy):
		return
	var next_cost: int = int(up.get("next_cost", -1))
	if next_cost < 0:
		buy.text = "Maxed"
		buy.disabled = true
		buy.tooltip_text = ""
	else:
		buy.text = "Buy (%d)" % next_cost
		buy.disabled = not can_upgrade or treasury < next_cost
		buy.tooltip_text = "Not enough Guild Funds." if (can_upgrade and treasury < next_cost) else ""


## Buy the next level of a Guild Hall upgrade. Server gates permission + cost;
## on success the open modal is refreshed in place (no flicker / scroll reset).
func _buy_upgrade(upgrade_id: String) -> void:
	if upgrade_id.is_empty():
		return
	Client.request_data(&"guild.hall.upgrade", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't upgrade.")))
			return
		Toaster.toast("%s upgraded to Lv %d." % [
			str(data.get("upgrade", "Upgrade")), int(data.get("level", 0))])
		_refresh_hall_in_place(),
		{"id": int(_guild.get("id", 0)), "upgrade": upgrade_id}, _inst())


## Deposit [param amount] gold into the active guild's treasury. Server gates it
## (membership + gold balance); on success the open modal is refreshed in place.
func _deposit_treasury(amount: int) -> void:
	if amount <= 0:
		return
	Client.request_data(&"guild.treasury.deposit", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't deposit.")))
			return
		Toaster.toast("Deposited %d to the treasury." % int(data.get("deposited", amount)))
		_refresh_hall_in_place(),
		{"id": int(_guild.get("id", 0)), "amount": amount}, _inst())


## Re-fetch the guild and update the open Hall modal's widgets IN PLACE — no
## close/reopen, so no flicker and the scroll position is preserved. Also quietly
## rebuilds the side panel behind the overlay (member count etc. may have changed).
func _refresh_hall_in_place() -> void:
	if _selected_name == "":
		return
	Client.request_data(&"guild.get", func(data: Dictionary) -> void:
		if not data.has("name"):
			return
		_guild = data
		_rebuild_right()
		_hall_apply_data(),
		{"q": _selected_name}, _inst())


## Push current _guild data into the open Hall widgets. Safe if the modal was
## closed in the meantime (every write guards on is_instance_valid).
func _hall_apply_data() -> void:
	if is_instance_valid(_hall_balance_label):
		_hall_balance_label.text = "%d  Guild Funds" % int(_guild.get("treasury", 0))
	if is_instance_valid(_hall_caps_label):
		_hall_caps_label.text = "Tag cap: %d online\nRoster: %d / %d" % [
			int(_guild.get("tag_cap", 15)), int(_guild.get("size", 0)), int(_guild.get("max_members", 25))]
	var gold: int = int(_guild.get("viewer_gold", 0))
	if is_instance_valid(_hall_gold_label):
		_hall_gold_label.text = "You have %d gold" % gold
	if is_instance_valid(_hall_deposit_spin):
		_hall_deposit_spin.max_value = maxi(gold, 0)
	var can_upgrade: bool = (int(_guild.get("permissions", 0)) & Guild.Permissions.EDIT) != 0
	var treasury: int = int(_guild.get("treasury", 0))
	for up: Dictionary in _guild.get("hall_upgrades", []):
		var id: String = str(up.get("id", ""))
		if _hall_rows.has(id):
			_update_upgrade_row(_hall_rows[id], up, can_upgrade, treasury)


func _view_settings(parent: Node) -> void:
	var box: VBoxContainer = _padded(parent)

	var back: Button = Button.new()
	back.text = "←  More"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.pressed.connect(func() -> void: _select_section("more"))
	box.add_child(back)
	box.add_child(HSeparator.new())

	var perms: int = int(_guild.get("permissions", 0))
	var can_edit: bool = (perms & Guild.Permissions.EDIT) != 0

	box.add_child(_make_section_header("Description"))

	var edit: TextEdit = TextEdit.new()
	edit.text = str(_guild.get("description", ""))
	edit.custom_minimum_size = Vector2(0, 90)
	edit.editable = can_edit
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(edit)

	if can_edit:
		# Logo picker — choose among the preset logos for alpha (custom upload
		# later). The selected one is the ButtonGroup's pressed button.
		box.add_child(_make_section_header("Logo"))
		var current_logo: int = int(_guild.get("logo_id", 0))
		var logo_group: ButtonGroup = ButtonGroup.new()
		var logo_row: HBoxContainer = HBoxContainer.new()
		logo_row.add_theme_constant_override(&"separation", 8)
		box.add_child(logo_row)
		# Clear selection feedback: selected logo gets a thick amber frame,
		# others a faint one (the theme's default pressed look is too subtle
		# behind an icon).
		var logo_selected: StyleBoxFlat = StyleBoxFlat.new()
		logo_selected.bg_color = Color(0.1, 0.21, 0.34, 1)
		logo_selected.set_border_width_all(3)
		logo_selected.border_color = Color(0.96, 0.74, 0.16)
		logo_selected.set_corner_radius_all(4)
		var logo_normal: StyleBoxFlat = StyleBoxFlat.new()
		logo_normal.bg_color = Color(0.06, 0.078, 0.117, 0.6)
		logo_normal.set_border_width_all(1)
		logo_normal.border_color = Color(0, 0, 0, 0.4)
		logo_normal.set_corner_radius_all(4)
		for i: int in LOGOS.size():
			var logo_btn: Button = Button.new()
			logo_btn.toggle_mode = true
			logo_btn.button_group = logo_group
			logo_btn.custom_minimum_size = Vector2(64, 64)
			logo_btn.icon = LOGOS[i]
			logo_btn.expand_icon = true
			logo_btn.button_pressed = (i == current_logo)
			logo_btn.set_meta(&"logo_id", i)
			logo_btn.add_theme_stylebox_override(&"normal", logo_normal)
			logo_btn.add_theme_stylebox_override(&"hover", logo_normal)
			logo_btn.add_theme_stylebox_override(&"pressed", logo_selected)
			logo_btn.add_theme_stylebox_override(&"hover_pressed", logo_selected)
			logo_row.add_child(logo_btn)

		var save: Button = Button.new()
		save.text = "Save changes"
		save.custom_minimum_size = Vector2(0, 36)
		save.pressed.connect(func() -> void:
			var logo_id: int = current_logo
			var pressed: Button = logo_group.get_pressed_button()
			if pressed != null:
				logo_id = int(pressed.get_meta(&"logo_id"))
			_save_guild_edits(edit.text, logo_id))
		box.add_child(save)
	else:
		var hint: Label = Label.new()
		hint.text = "You don't have permission to edit the guild."
		hint.modulate.a = 0.55
		hint.add_theme_font_size_override(&"font_size", 12)
		box.add_child(hint)


# ---------------------------------------------------------------------------
# Create / Browse views
# ---------------------------------------------------------------------------

func _show_create() -> void:
	_selected_name = ""
	_clear_left_selection()
	for child: Node in _right_host.get_children():
		child.queue_free()
	var box: VBoxContainer = _padded(_right_host)

	box.add_child(_make_title("Create your own guild"))

	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text = "Guild name"
	name_edit.max_length = 21
	box.add_child(name_edit)

	var cost: Label = Label.new()
	cost.text = "Cost: %d gold" % Guild.CREATION_COST
	cost.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	box.add_child(cost)

	var status: Label = Label.new()
	status.add_theme_color_override(&"font_color", Color(0.95, 0.6, 0.55))
	box.add_child(status)

	var create: Button = Button.new()
	create.text = "Create"
	create.custom_minimum_size = Vector2(0, 40)
	box.add_child(create)
	create.pressed.connect(func() -> void:
		var gname: String = name_edit.text.strip_edges()
		if gname.is_empty():
			return
		create.disabled = true
		Client.request_data(&"guild.create", func(data: Dictionary) -> void:
			create.disabled = false
			if data.has("name"):
				_selected_name = str(data.get("name", ""))
				_refresh()
			else:
				status.text = str(data.get("message", "Could not create guild.")),
			{"name": gname}, _inst()))


func _show_browse() -> void:
	_selected_name = ""
	_clear_left_selection()
	for child: Node in _right_host.get_children():
		child.queue_free()
	var box: VBoxContainer = _padded(_right_host)

	box.add_child(_make_title("Browse guilds"))

	var search_row: HBoxContainer = HBoxContainer.new()
	search_row.add_theme_constant_override(&"separation", 8)
	box.add_child(search_row)
	var search_edit: LineEdit = LineEdit.new()
	search_edit.placeholder_text = "Guild name"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(search_edit)
	var search_btn: Button = Button.new()
	search_btn.text = "Search"
	search_row.add_child(search_btn)

	var results: VBoxContainer = VBoxContainer.new()
	results.add_theme_constant_override(&"separation", 4)
	box.add_child(results)

	var do_search: Callable = func() -> void:
		var q: String = search_edit.text.strip_edges()
		if q.is_empty():
			return
		Client.request_data(&"guild.search", func(data: Dictionary) -> void:
			for child: Node in results.get_children():
				child.queue_free()
			if data.is_empty() or data.has("error"):
				var nores: Label = Label.new()
				nores.text = "No guilds found."
				nores.modulate.a = 0.55
				results.add_child(nores)
				return
			for gname: String in data:
				var btn: Button = Button.new()
				btn.text = gname
				btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				btn.custom_minimum_size = Vector2(0, 36)
				btn.pressed.connect(_select_guild.bind(gname))
				results.add_child(btn),
			{"q": q}, _inst())
	search_btn.pressed.connect(do_search)
	search_edit.text_submitted.connect(func(_t: String) -> void: do_search.call())


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _save_guild_edits(description: String, logo_id: int) -> void:
	Client.request_data(&"guild.edit", func(_d: Dictionary) -> void:
		_select_guild(_selected_name),
		{"name": _selected_name, "description": description, "logo_id": logo_id},
		_inst())


func _leave_guild() -> void:
	var leaving: String = _selected_name
	Client.request_data(&"guild.quit", func(_d: Dictionary) -> void:
		_selected_name = ""
		_refresh(),
		{"guild_name": leaving}, _inst())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _show_message(text: String) -> void:
	for child: Node in _right_host.get_children():
		child.queue_free()
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate.a = 0.6
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_right_host.add_child(label)


## Adds a padded, SCROLLING VBox under [param parent] and returns it for content.
## The scroll is essential: without it a tall section (e.g. More, or a long
## description) grows the whole card past the screen edge.
func _padded(parent: Node) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 8)
	margin.add_child(box)
	return box


func _stat_row(label_text: String, value: int) -> Control:
	return _stat_row_str(label_text, str(value))


func _stat_row_str(label_text: String, value_text: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var name_label: Label = Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	row.add_child(name_label)
	var value_label: Label = Label.new()
	value_label.text = value_text
	value_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	row.add_child(value_label)
	return row


func _format_duration(seconds: int) -> String:
	@warning_ignore("integer_division")
	var hours: int = seconds / 3600
	@warning_ignore("integer_division")
	var minutes: int = (seconds % 3600) / 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes


func _make_title(text: String) -> Label:
	var title: Label = Label.new()
	title.text = text
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(&"font_color", COLOR_GOLD)
	return title


func _make_section_header(text: String) -> Label:
	var header: Label = Label.new()
	header.text = text
	header.add_theme_font_size_override(&"font_size", 13)
	header.add_theme_color_override(&"font_color", COLOR_SECTION)
	return header


func _section_exists(sections: Array, section: String) -> bool:
	for s: Array in sections:
		if str(s[0]) == section:
			return true
	return false


func _logo_for(logo_id: int) -> Texture2D:
	if logo_id >= 0 and logo_id < LOGOS.size():
		return LOGOS[logo_id]
	return LOGOS[0]


func _inst() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current else ""


func _is_joined(guild_name: String) -> bool:
	for g: Dictionary in _joined:
		if str(g.get("name", "")) == guild_name:
			return true
	return false


func _default_guild_name() -> String:
	for g: Dictionary in _joined:
		if bool(g.get("is_active", false)):
			return str(g.get("name", ""))
	if not _joined.is_empty():
		return str(_joined[0].get("name", ""))
	return ""
