extends MenuShell
## Guild menu — one full-screen view (rework 2026-07-19, replacing the old
## split view whose left column spent 40% width on a guild list most players
## never switch). Title bar owns everything: guild SWITCHER dropdown on the
## left (joined guilds + Create + Browse), Profile / Members / More section
## tabs in the center, Tag + Close on the right. Content renders full width
## in a centered column. Same layout grammar as guild_hall / mastery_tree.

const COLOR_GOLD: Color = Color(1.0, 0.95, 0.75)
const COLOR_SECTION: Color = Color(1.0, 0.85, 0.5)
const COLOR_MUTED: Color = Color(0.75, 0.77, 0.83)

## Content column width cap — full-width rows read poorly on wide screens.
const COLUMN_WIDTH: float = 560.0

var _content_host: PanelContainer
var _switcher_button: Button
var _tag_button: Button
## section key (String) -> tab Button in the header bar.
var _tab_buttons: Dictionary

var _joined: Array
## Name of the guild currently shown ("" = none / create / browse).
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
	build_shell("", null, true)
	# Frosted-glass backdrop + no inner panel, matching settings/inventory —
	# content (rows, buttons) sits directly on the blurred world.
	var blur: ShaderMaterial = ShaderMaterial.new()
	blur.shader = load("res://source/client/ui/shared/menu_blur_backdrop.gdshader")
	blur.set_shader_parameter(&"blur_lod", 2.5)
	blur.set_shader_parameter(&"dim_color", Color(0.073365234, 0.08239203, 0.122337736, 0.55))
	backdrop.material = blur
	_build_header()

	_content_host = PanelContainer.new()
	_content_host.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_content_host)

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


## Header bar widgets: switcher (far left, replaces the shell title), section
## tabs (center slot), Tag button (right slot, before Close). The switcher is
## the old left column folded into a dropdown — switching guilds is rare, so
## it costs a tap instead of permanent screen width.
func _build_header() -> void:
	var header: HBoxContainer = header_center.get_parent() as HBoxContainer

	# True centering: the tabs sit between TWO equal expanders. The switcher
	# must live INSIDE the left expander (mirroring Tag/Close inside
	# header_right) — placed outside it, it shoves the tabs off center by half
	# its own width. The shell's empty title label is hidden so it stops
	# acting as a second left spacer.
	for child: Node in header.get_children():
		if child is Label:
			(child as Label).visible = false
			break
	var left_box: HBoxContainer = HBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left_box)
	header.move_child(left_box, 0)

	_switcher_button = Button.new()
	_switcher_button.custom_minimum_size = Vector2(0, 36)
	_switcher_button.expand_icon = true
	_switcher_button.add_theme_color_override(&"font_color", COLOR_GOLD)
	_switcher_button.pressed.connect(_open_switcher)
	left_box.add_child(_switcher_button)

	for s: Array in [["profile", "Profile"], ["members", "Members"], ["more", "More"]]:
		var btn: Button = Button.new()
		btn.text = s[1]
		btn.theme_type_variation = &"SectionTab"
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(96, 32)
		btn.pressed.connect(_select_section.bind(str(s[0])))
		header_center.add_child(btn)
		_tab_buttons[s[0]] = btn

	_tag_button = Button.new()
	_tag_button.custom_minimum_size = Vector2(90, 34)
	_tag_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tag_button.tooltip_text = "Set this as your active guild (safe zone only)."
	_tag_button.visible = false
	_tag_button.pressed.connect(_on_tag_pressed)
	header_right.add_child(_tag_button)
	header_right.move_child(_tag_button, 0)


# ---------------------------------------------------------------------------
# Data flow — joined guilds -> selected guild -> view
# ---------------------------------------------------------------------------

func _refresh() -> void:
	Client.request_data(&"guild.get.joined_guilds", _on_joined, {}, _inst())


func _on_joined(data: Dictionary) -> void:
	_joined = data.get("guilds", [])
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
		_guild = {}
		_show_empty_state()


func _select_guild(guild_name: String) -> void:
	_selected_name = guild_name
	Client.request_data(&"guild.get", _on_guild_loaded, {"q": guild_name}, _inst())


func _on_guild_loaded(data: Dictionary) -> void:
	if not data.has("name"):
		_show_message("Guild not found.")
		return
	_guild = data
	_section = "profile"
	_rebuild_view()


## The switcher dropdown: joined guilds (★ = tagged), then Create / Browse.
## Same overlay technique as the member-manage popup, anchored to the button.
func _open_switcher() -> void:
	var overlay: Control = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.35)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			overlay.queue_free())
	overlay.add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 0)
	panel.position = _switcher_button.global_position - global_position \
		+ Vector2(0, _switcher_button.size.y + 4)
	overlay.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	panel.add_child(box)

	var pick: Callable = func(gname: String) -> void:
		overlay.queue_free()
		_select_guild(gname)

	for g: Dictionary in _joined:
		var gname: String = str(g.get("name", "?"))
		var entry: Button = Button.new()
		entry.text = ("★ " if bool(g.get("is_active", false)) else "") + gname
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.custom_minimum_size = Vector2(0, 38)
		entry.toggle_mode = true
		entry.button_pressed = (gname == _selected_name)
		entry.pressed.connect(pick.bind(gname))
		box.add_child(entry)
	# A foreign guild being viewed (Show Guild) appears too, so the switcher
	# always reflects what's on screen.
	if _selected_name != "" and not _is_joined(_selected_name):
		var viewing: Button = Button.new()
		viewing.text = _selected_name + "   (viewing)"
		viewing.alignment = HORIZONTAL_ALIGNMENT_LEFT
		viewing.custom_minimum_size = Vector2(0, 38)
		viewing.toggle_mode = true
		viewing.button_pressed = true
		viewing.pressed.connect(pick.bind(_selected_name))
		box.add_child(viewing)

	box.add_child(HSeparator.new())
	var create: Button = Button.new()
	create.text = "+  Create guild"
	create.alignment = HORIZONTAL_ALIGNMENT_LEFT
	create.custom_minimum_size = Vector2(0, 38)
	create.pressed.connect(func() -> void:
		overlay.queue_free()
		_show_create())
	box.add_child(create)
	var browse: Button = Button.new()
	browse.text = "Browse guilds"
	browse.alignment = HORIZONTAL_ALIGNMENT_LEFT
	browse.custom_minimum_size = Vector2(0, 38)
	browse.pressed.connect(func() -> void:
		overlay.queue_free()
		_show_browse())
	box.add_child(browse)


# ---------------------------------------------------------------------------
# View dispatch — header state + active section into the content host
# ---------------------------------------------------------------------------

func _rebuild_view() -> void:
	var is_member: bool = bool(_guild.get("is_member", false))

	# Non-members can't reach the More hub or its sub-views.
	if not is_member and _section in ["more", "settings", "log"]:
		_section = "profile"
	_update_header()

	for child: Node in _content_host.get_children():
		child.queue_free()
	match _section:
		"members":
			_view_members(_content_host)
		"more":
			_view_more(_content_host)
		"settings":
			_view_settings(_content_host)
		"log":
			_view_log(_content_host)
		_:
			_view_profile(_content_host)


## Sync the title-bar widgets to the selected guild: switcher emblem + name,
## tab visibility/highlight ("settings"/"log" keep More lit), Tag button text.
func _update_header() -> void:
	var has_guild: bool = _selected_name != "" and _guild.has("name")
	var is_member: bool = bool(_guild.get("is_member", false))

	_switcher_button.icon = _logo_for(int(_guild.get("logo_id", 0))) if has_guild else null
	_switcher_button.text = ("%s  ▾" % _selected_name) if has_guild else "Guild  ▾"

	var active_tab: String = "more" if _section in ["settings", "log"] else _section
	for key: String in _tab_buttons:
		var btn: Button = _tab_buttons[key]
		btn.visible = has_guild and (key != "more" or is_member)
		btn.button_pressed = has_guild and (key == active_tab)

	_tag_button.visible = is_member
	_tag_button.text = "Untag ★" if bool(_guild.get("is_active", false)) else "Tag"


func _select_section(section: String) -> void:
	_section = section
	_rebuild_view()


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

	# Identity row: logo + name / leader / member count / description. This
	# used to live in the old right-column header — now it's the tab's content.
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 16)
	box.add_child(top)

	var big_logo: TextureRect = TextureRect.new()
	# EXPAND_IGNORE_SIZE pins the node to custom_minimum_size no matter how tall
	# the row gets — a long description must never inflate the logo. SHRINK_CENTER
	# keeps the HBox from stretching it vertically.
	big_logo.custom_minimum_size = Vector2(96, 96)
	big_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	big_logo.texture = _logo_for(int(_guild.get("logo_id", 0)))
	top.add_child(big_logo)

	var id_col: VBoxContainer = VBoxContainer.new()
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(id_col)

	var name_label: Label = Label.new()
	name_label.text = str(_guild.get("name", "?"))
	name_label.add_theme_font_size_override(&"font_size", 20)
	name_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	id_col.add_child(name_label)

	var sub: Label = Label.new()
	sub.text = "Leader: %s   ·   %d / %d members" % [
		str(_guild.get("leader_name", "?")),
		int(_guild.get("size", 0)),
		int(_guild.get("max_members", Guild.MAX_MEMBERS)),
	]
	sub.add_theme_color_override(&"font_color", COLOR_MUTED)
	sub.add_theme_font_size_override(&"font_size", 12)
	id_col.add_child(sub)

	var desc: String = str(_guild.get("description", ""))
	# RichTextLabel with fit_content OFF: fixed-height box that scrolls
	# internally when the text overflows — the row's size is CONSTANT
	# regardless of description length. Also immune to the autowrap-Label-in-HBox
	# min-size oscillation that used to hard-crash this view. bbcode stays OFF —
	# descriptions are player-written, no tag injection.
	var desc_label: RichTextLabel = RichTextLabel.new()
	desc_label.bbcode_enabled = true
	desc_label.fit_content = false
	desc_label.scroll_active = true
	desc_label.custom_minimum_size = Vector2(0, 64)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.text = desc if not desc.is_empty() else "No description."
	desc_label.add_theme_color_override(&"default_color", COLOR_MUTED)
	id_col.add_child(desc_label)

	box.add_child(HSeparator.new())

	# Stats (members is on the header bar, so it's omitted here).
	box.add_child(_make_section_header("Stats"))
	box.add_child(_stat_row("Kills", int(_guild.get("total_kills", 0))))
	box.add_child(_stat_row_str("Base time", _format_duration(int(_guild.get("territory_seconds", 0)))))
	box.add_child(_stat_row("Seasonal glory", int(_guild.get("seasonal_glory", 0))))
	box.add_child(_stat_row("Eternal glory", int(_guild.get("eternal_glory", 0))))
	box.add_child(_stat_row("Spar rating", int(_guild.get("spar_score", 0))))

	# Trophies are read-only here — the Profile tab stays static; picking
	# happens in Settings (single editing place, owner call).
	box.add_child(_make_section_header("Trophies"))
	var displayed: Array = _guild.get("displayed_trophies", [])
	if displayed.is_empty():
		var none: Label = Label.new()
		none.text = "No trophies displayed yet. Earn them through guild feats."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_color_override(&"font_color", COLOR_MUTED)
		none.add_theme_font_size_override(&"font_size", 12)
		box.add_child(none)
	else:
		var chips: HBoxContainer = HBoxContainer.new()
		chips.add_theme_constant_override(&"separation", 8)
		box.add_child(chips)
		for tid: Variant in displayed:
			chips.add_child(_trophy_chip(StringName(str(tid))))


## Flat chip for one displayed trophy (matches the frosted no-panel style).
## Tapping it toasts the trophy's description — the mobile-safe "tooltip"
## (hover tooltip_text still works on desktop for free).
func _trophy_chip(trophy_id: StringName) -> Control:
	var desc: String = str(GuildTrophies.CATALOG.get(trophy_id, {}).get("desc", ""))
	var chip: Button = Button.new()
	chip.flat = true
	chip.custom_minimum_size = Vector2(0, 40)
	chip.tooltip_text = desc
	chip.focus_mode = Control.FOCUS_NONE
	chip.pressed.connect(func() -> void:
		Toaster.toast("%s: %s" % [GuildTrophies.display_name(trophy_id), desc]))

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 6)
	chip.add_child(row)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path: String = GuildTrophies.icon_path(trophy_id)
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	row.add_child(icon)

	var name_label: Label = Label.new()
	name_label.text = GuildTrophies.display_name(trophy_id)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	name_label.add_theme_font_size_override(&"font_size", 13)
	row.add_child(name_label)

	# The row is a manual child (not button text/icon), so size the chip to it.
	chip.custom_minimum_size = Vector2(46 + name_label.get_theme_font(&"font").get_string_size(
		name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 40)
	return chip


## Trophy case popup: every catalog trophy with unlock state + live progress;
## EDIT holders pick up to GuildTrophies.MAX_DISPLAYED for the profile.
func _open_trophy_case() -> void:
	Client.request_data(&"guild.trophies.get", _show_trophy_case, {"q": _selected_name}, _inst())


func _show_trophy_case(data: Dictionary) -> void:
	if not bool(data.get("ok", false)):
		Toaster.toast(str(data.get("message", "Couldn't open the trophy case.")))
		return
	var can_edit: bool = bool(data.get("can_edit", false))
	var displayed: Array = data.get("displayed", [])

	var card: VBoxContainer = _confirm_card("Trophy case")
	if can_edit:
		var hint: Label = Label.new()
		hint.text = "Pick up to %d to display on the guild profile." % GuildTrophies.MAX_DISPLAYED
		hint.add_theme_color_override(&"font_color", COLOR_MUTED)
		hint.add_theme_font_size_override(&"font_size", 12)
		card.add_child(hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 340)
	card.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(list)
	DragScroll.enable(scroll)

	var checks: Array[CheckBox] = []
	for entry: Dictionary in data.get("entries", []):
		var unlocked: bool = bool(entry.get("unlocked", false))
		var row: PanelContainer = PanelContainer.new()
		var pad: MarginContainer = MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 8)
		row.add_child(pad)
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override(&"separation", 10)
		pad.add_child(hbox)

		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color.WHITE if unlocked else Color(0.4, 0.4, 0.45)
		var icon_path: String = GuildTrophies.icon_path(StringName(str(entry.get("id", ""))))
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		hbox.add_child(icon)

		var info: VBoxContainer = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info)
		var name_label: Label = Label.new()
		name_label.text = str(entry.get("name", "?"))
		name_label.add_theme_color_override(&"font_color", COLOR_GOLD if unlocked else COLOR_MUTED)
		info.add_child(name_label)
		var desc: Label = Label.new()
		desc.text = str(entry.get("desc", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override(&"font_color", COLOR_MUTED)
		desc.add_theme_font_size_override(&"font_size", 11)
		info.add_child(desc)

		var progress: Label = Label.new()
		progress.text = "Unlocked" if unlocked else str(entry.get("progress_text", ""))
		progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress.add_theme_color_override(
			&"font_color", Color(0.55, 0.85, 0.95) if unlocked else COLOR_MUTED)
		progress.add_theme_font_size_override(&"font_size", 12)
		hbox.add_child(progress)

		if can_edit and unlocked:
			var pick: CheckBox = CheckBox.new()
			pick.button_pressed = displayed.has(entry.get("id", ""))
			pick.set_meta(&"trophy_id", str(entry.get("id", "")))
			pick.toggled.connect(func(_on: bool) -> void: _enforce_trophy_cap(checks))
			hbox.add_child(pick)
			checks.append(pick)
		list.add_child(row)
	_enforce_trophy_cap(checks)

	if can_edit:
		var save_btn: Button = _confirm_buttons(card, "Save picks", true, func() -> void:
			var picks: Array = []
			for c: CheckBox in checks:
				if c.button_pressed:
					picks.append(c.get_meta(&"trophy_id"))
			Client.request_data(&"guild.trophies.display", func(d: Dictionary) -> void:
				if not bool(d.get("ok", false)):
					Toaster.toast(str(d.get("message", "Couldn't save picks.")))
					return
				_refresh_current(),
				{"q": _selected_name, "picks": picks}, _inst()))
		save_btn.add_theme_color_override(&"font_color", COLOR_GOLD)
	else:
		var close_row: HBoxContainer = HBoxContainer.new()
		card.add_child(HSeparator.new())
		card.add_child(close_row)
		var close_btn: Button = Button.new()
		close_btn.text = "Close"
		close_btn.custom_minimum_size = Vector2(0, 38)
		close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		close_btn.pressed.connect(func() -> void:
			(card.get_meta(&"overlay") as Node).queue_free())
		close_row.add_child(close_btn)


## Live pick-cap enforcement: at MAX_DISPLAYED checked, unchecked boxes lock.
func _enforce_trophy_cap(checks: Array[CheckBox]) -> void:
	var picked: int = 0
	for c: CheckBox in checks:
		if is_instance_valid(c) and c.button_pressed:
			picked += 1
	for c: CheckBox in checks:
		if is_instance_valid(c):
			c.disabled = picked >= GuildTrophies.MAX_DISPLAYED and not c.button_pressed


func _view_members(parent: Node) -> void:
	var vbox: VBoxContainer = _padded(parent)
	vbox.add_theme_constant_override(&"separation", 4)
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

	# Leader-only: hand the guild over (any member, even offline — see
	# docs/guild.md). Confirmed in a follow-up dialog.
	if bool(viewer.get("is_leader", false)):
		var crown: Button = Button.new()
		crown.text = "Make leader"
		crown.custom_minimum_size = Vector2(0, 36)
		crown.pressed.connect(func() -> void:
			overlay.queue_free()
			_confirm_transfer(member))
		left.add_child(crown)

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
			_rebuild_view(),
		{"q": _selected_name}, _inst())


## The "More" hub — Settings plus space for future guild features. Settings is
## live; the rest are placeholders that signal the roadmap (see docs/guild.md).
func _view_more(parent: Node) -> void:
	var box: VBoxContainer = _padded(parent)
	# Guild Hall is its own full-screen menu now (mastery-tree pattern), not a
	# modal — it layers over this menu and closes back to it.
	box.add_child(_more_entry("Guild Hall", true, func() -> void:
		ClientState.open_menu_requested.emit(&"guild_hall", _selected_name)))
	box.add_child(_more_entry("Log", true, func() -> void: _select_section("log")))
	box.add_child(_more_entry("Settings", true, func() -> void: _select_section("settings")))
	box.add_child(_more_entry("Trophies", true, _open_trophy_case))
	box.add_child(_more_entry("Allies", false, Callable()))
	box.add_child(_more_entry("Island", false, Callable()))

	box.add_child(HSeparator.new())
	if bool(_guild.get("is_leader", false)):
		var leader_note: Label = Label.new()
		leader_note.text = "To hand off leadership, open a member on the Members tab and choose Make Leader."
		leader_note.modulate.a = 0.55
		leader_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		leader_note.add_theme_font_size_override(&"font_size", 12)
		box.add_child(leader_note)
		var disband: Button = Button.new()
		disband.text = "Disband guild"
		disband.alignment = HORIZONTAL_ALIGNMENT_LEFT
		disband.custom_minimum_size = Vector2(0, 42)
		disband.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		disband.add_theme_color_override(&"font_color", Color(0.95, 0.6, 0.55))
		disband.pressed.connect(_confirm_disband)
		box.add_child(disband)
	else:
		var leave: Button = Button.new()
		leave.text = "Leave guild"
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


## The guild event log (members only): joins, leaves, kicks, ranks, deposits,
## upgrade buys, territory captures/losses. Newest first, server-formatted text.
func _view_log(parent: Node) -> void:
	var box: VBoxContainer = _padded(parent)

	var back: Button = Button.new()
	back.text = "←  More"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.pressed.connect(func() -> void: _select_section("more"))
	box.add_child(back)
	box.add_child(HSeparator.new())
	box.add_child(_make_section_header("Guild Log"))

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 4)
	box.add_child(list)

	Client.request_data(&"guild.log.get", func(data: Dictionary) -> void:
		_fill_log(list, data), {"q": _selected_name}, _inst())


func _fill_log(list: VBoxContainer, data: Dictionary) -> void:
	if not is_instance_valid(list):
		return
	var entries: Array = data.get("entries", [])
	if not bool(data.get("ok", false)) or entries.is_empty():
		var none: Label = Label.new()
		none.text = "Nothing logged yet."
		none.modulate.a = 0.55
		none.add_theme_font_size_override(&"font_size", 12)
		list.add_child(none)
		return
	for entry: Dictionary in entries:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		list.add_child(row)

		var when: Label = Label.new()
		when.text = _time_ago(int(entry.get("time_ms", 0)))
		when.custom_minimum_size = Vector2(52, 0)
		when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		when.add_theme_color_override(&"font_color", COLOR_MUTED)
		when.add_theme_font_size_override(&"font_size", 11)
		row.add_child(when)

		var text: Label = Label.new()
		text.text = str(entry.get("text", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override(&"font_size", 12)
		row.add_child(text)


## Compact "how long ago" for log rows ("now", "5m", "3h", "12d").
func _time_ago(unix_ms: int) -> String:
	if unix_ms <= 0:
		return ""
	@warning_ignore("integer_division")
	var secs: int = maxi(0, int(Time.get_unix_time_from_system()) - unix_ms / 1000)
	if secs < 60:
		return "now"
	if secs < 3600:
		@warning_ignore("integer_division")
		return "%dm" % (secs / 60)
	if secs < 86400:
		@warning_ignore("integer_division")
		return "%dh" % (secs / 3600)
	@warning_ignore("integer_division")
	return "%dd" % (secs / 86400)


func _view_settings(parent: Node) -> void:
	# Scrollable fields on top, Save PINNED in a bottom bar outside the scroll —
	# it can never scroll off screen again (the old layout needed scrolling to
	# reach Save even on desktop).
	var outer: VBoxContainer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(outer)
	var box: VBoxContainer = _padded(outer)

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

	# Emblem: shown here, MANAGED in the Guild Hall (single editing place —
	# emblems are cosmetics, so their buy/equip catalog lives with the rest).
	box.add_child(_make_section_header("Emblem"))
	var emblem_row: HBoxContainer = HBoxContainer.new()
	emblem_row.add_theme_constant_override(&"separation", 12)
	box.add_child(emblem_row)
	var current_emblem: TextureRect = TextureRect.new()
	current_emblem.custom_minimum_size = Vector2(48, 48)
	current_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	current_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	current_emblem.texture = _logo_for(int(_guild.get("logo_id", 0)))
	emblem_row.add_child(current_emblem)
	var change_emblem: Button = Button.new()
	change_emblem.text = "Change emblem"
	change_emblem.custom_minimum_size = Vector2(160, 36)
	change_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	change_emblem.pressed.connect(func() -> void:
		ClientState.open_menu_requested.emit(&"guild_emblems", _selected_name))
	emblem_row.add_child(change_emblem)

	if can_edit:
		# Pinned bottom bar — attached to the outer VBox, below the scroll.
		outer.add_child(HSeparator.new())
		var save_bar: HBoxContainer = HBoxContainer.new()
		save_bar.alignment = BoxContainer.ALIGNMENT_END
		outer.add_child(save_bar)
		var save: Button = Button.new()
		save.text = "Save changes"
		save.custom_minimum_size = Vector2(160, 38)
		save.pressed.connect(func() -> void:
			_save_guild_edits(edit.text))
		save_bar.add_child(save)
	else:
		var hint: Label = Label.new()
		hint.text = "You don't have permission to edit the guild."
		hint.modulate.a = 0.55
		hint.add_theme_font_size_override(&"font_size", 12)
		box.add_child(hint)

	# Trophy case lives here with the other guild editing (the Profile tab
	# stays read-only). Any member can browse; picking needs EDIT.
	box.add_child(_make_section_header("Trophies"))
	var case_btn: Button = Button.new()
	case_btn.text = "Trophy case"
	case_btn.custom_minimum_size = Vector2(180, 36)
	case_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	case_btn.pressed.connect(_open_trophy_case)
	box.add_child(case_btn)


# ---------------------------------------------------------------------------
# Create / Browse views
# ---------------------------------------------------------------------------

func _show_create() -> void:
	_selected_name = ""
	_guild = {}
	_section = "create"
	_update_header()
	for child: Node in _content_host.get_children():
		child.queue_free()
	var box: VBoxContainer = _padded(_content_host)

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
	_guild = {}
	_section = "browse"
	_update_header()
	for child: Node in _content_host.get_children():
		child.queue_free()
	var box: VBoxContainer = _padded(_content_host)

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

## Saves the description only — the emblem is equipped from the emblem catalog
## (guild.edit treats both fields as optional).
func _save_guild_edits(description: String) -> void:
	Client.request_data(&"guild.edit", func(_d: Dictionary) -> void:
		_select_guild(_selected_name),
		{"name": _selected_name, "description": description},
		_inst())


func _leave_guild() -> void:
	var leaving: String = _selected_name
	Client.request_data(&"guild.quit", func(_d: Dictionary) -> void:
		_selected_name = ""
		_refresh(),
		{"guild_name": leaving}, _inst())


## Yes/no confirm before handing leadership over. A plain dialog is enough —
## the new leader can always hand it back (unlike disband).
func _confirm_transfer(member: Dictionary) -> void:
	var target_name: String = str(member.get("name", "?"))
	var target_id: int = int(member.get("id", 0))
	var card: VBoxContainer = _confirm_card("Hand leadership of %s to %s?" % [_selected_name, target_name])

	var body: Label = Label.new()
	body.text = "You keep your rank but lose leader powers. Only %s can hand them back." % target_name
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", COLOR_MUTED)
	body.add_theme_font_size_override(&"font_size", 13)
	card.add_child(body)

	_confirm_buttons(card, "Transfer leadership", true, func() -> void:
		Client.request_data(&"guild.transfer", func(data: Dictionary) -> void:
			Toaster.toast(str(data.get("message", "Done.")))
			_refresh(),
			{"guild_name": _selected_name, "target_id": target_id}, _inst()))


## Type-the-guild-name confirm before disband — it's permanent (members
## removed, territories released, treasury and log deleted).
func _confirm_disband() -> void:
	var disbanding: String = _selected_name
	var card: VBoxContainer = _confirm_card("Disband %s?" % disbanding)

	var body: Label = Label.new()
	body.text = "This is permanent. Every member is removed, held territories are released, and the treasury and log are lost."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", COLOR_MUTED)
	body.add_theme_font_size_override(&"font_size", 13)
	card.add_child(body)

	var prompt: Label = Label.new()
	prompt.text = "Type the guild name to confirm:"
	prompt.add_theme_font_size_override(&"font_size", 12)
	card.add_child(prompt)
	var confirm_edit: LineEdit = LineEdit.new()
	confirm_edit.placeholder_text = disbanding
	card.add_child(confirm_edit)

	var confirm_btn: Button = _confirm_buttons(card, "Disband forever", false, func() -> void:
		Client.request_data(&"guild.disband", func(data: Dictionary) -> void:
			if not bool(data.get("ok", false)):
				Toaster.toast(str(data.get("message", "Couldn't disband.")))
				return
			Toaster.toast("Guild disbanded.")
			_selected_name = ""
			_guild = {}
			_refresh(),
			{"guild_name": disbanding, "confirm": confirm_edit.text.strip_edges()}, _inst()))
	confirm_edit.text_changed.connect(func(text: String) -> void:
		confirm_btn.disabled = text.strip_edges() != disbanding)


## Builds a centered modal confirm card (dim closes it) and returns its VBox
## for content. Pair with _confirm_buttons for the action row.
func _confirm_card(title_text: String) -> VBoxContainer:
	var overlay: Control = Control.new()
	overlay.name = "ConfirmOverlay"
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

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(pad)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	pad.add_child(box)

	var title: Label = Label.new()
	title.text = title_text
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override(&"font_size", 17)
	title.add_theme_color_override(&"font_color", COLOR_GOLD)
	box.add_child(title)
	# Direct overlay ref for _confirm_buttons — walking get_parent() chains to
	# find it is how a menu accidentally frees itself.
	box.set_meta(&"overlay", overlay)
	return box


## Adds the Cancel / red-confirm row to a _confirm_card. Returns the confirm
## button (so a caller can gate it, e.g. type-to-confirm). Confirm also closes
## the card before running [param on_confirm].
func _confirm_buttons(card: VBoxContainer, confirm_label: String, start_enabled: bool, on_confirm: Callable) -> Button:
	card.add_child(HSeparator.new())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	card.add_child(row)

	var overlay: Node = card.get_meta(&"overlay")
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 38)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: overlay.queue_free())
	row.add_child(cancel)

	var confirm: Button = Button.new()
	confirm.text = confirm_label
	confirm.custom_minimum_size = Vector2(0, 38)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.disabled = not start_enabled
	confirm.add_theme_color_override(&"font_color", Color(0.95, 0.6, 0.55))
	confirm.pressed.connect(func() -> void:
		overlay.queue_free()
		on_confirm.call())
	row.add_child(confirm)
	return confirm


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _show_message(text: String) -> void:
	for child: Node in _content_host.get_children():
		child.queue_free()
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate.a = 0.6
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_content_host.add_child(label)


## Guildless onboarding: big Create / Browse actions front and center instead
## of a bare "you're not in a guild" message.
func _show_empty_state() -> void:
	_section = "empty"
	_update_header()
	for child: Node in _content_host.get_children():
		child.queue_free()
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override(&"separation", 10)
	center.add_child(box)

	var title: Label = _make_title("No guild yet")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub: Label = Label.new()
	sub.text = "Found your own or find one to join."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override(&"font_color", COLOR_MUTED)
	sub.add_theme_font_size_override(&"font_size", 13)
	box.add_child(sub)

	var create: Button = Button.new()
	create.text = "Create guild  (%d gold)" % Guild.CREATION_COST
	create.custom_minimum_size = Vector2(0, 44)
	create.pressed.connect(_show_create)
	box.add_child(create)
	var browse: Button = Button.new()
	browse.text = "Browse guilds"
	browse.custom_minimum_size = Vector2(0, 44)
	browse.pressed.connect(_show_browse)
	box.add_child(browse)


## Adds a padded, SCROLLING, width-capped centered VBox under [param parent]
## and returns it for content. The scroll is essential: without it a tall
## section grows past the screen edge. The COLUMN_WIDTH cap keeps full-width
## sections readable on wide screens (rows don't stretch edge to edge).
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
	box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override(&"separation", 8)
	margin.add_child(box)
	DragScroll.enable(scroll)
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


func _logo_for(logo_id: int) -> Texture2D:
	return GuildLogos.texture(logo_id)


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
