extends VBoxContainer
## Lists the player's professions compactly (level + xp bar + xp amount, with a perk-
## point badge). Each one has a Details button opening a modal overlay with the
## effective bonuses and the perk picker — so the tab stays small no matter how many
## jobs exist.

@onready var skill_list: VBoxContainer = %SkillList

var _skills: Dictionary
## Full-rect modal that dims + blocks the menu behind it while a job's detail is open.
var _overlay: Control
var _detail_root: VBoxContainer
## Skill currently shown in the detail overlay ("" when closed).
var _open_skill: String


func _ready() -> void:
	ClientState.gather_succeeded.connect(func(_result: Dictionary): _refresh())
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()
	else:
		# Don't leave the detail overlay floating when the tab/menu is hidden.
		_close_detail()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	Client.request_data(&"skills.get", _on_skills_received, {}, InstanceClient.current.name)


func _on_skills_received(data: Dictionary) -> void:
	_skills = data.get("skills", {})
	_rebuild_list()
	if _open_skill != "" and _skills.has(_open_skill):
		_rebuild_detail()


# --- Compact list ---

func _rebuild_list() -> void:
	for child in skill_list.get_children():
		child.queue_free()

	if _skills.is_empty():
		var empty: Label = Label.new()
		empty.text = "No professions trained yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skill_list.add_child(empty)
		return

	for skill_name in _skills:
		skill_list.add_child(_make_list_row(String(skill_name), _skills[skill_name]))


func _make_list_row(skill_name: String, info: Dictionary) -> PanelContainer:
	var skill_level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var xp_to_next: int = int(info.get("xp_to_next", 1))
	var points: int = int(info.get("points", 0))
	var has_perks: bool = info.has("choices")

	var panel: PanelContainer = PanelContainer.new()

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 8)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_theme_constant_override(&"margin_bottom", 6)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 2)
	margin.add_child(vbox)

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	vbox.add_child(head)

	var name_label: Label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = "%s — Lv %d" % [skill_name.capitalize(), skill_level]
	head.add_child(name_label)

	# Perk-point badge so an unspent point is visible at a glance.
	if has_perks and points > 0:
		var badge: Label = Label.new()
		badge.text = "● %d" % points
		badge.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.2))
		head.add_child(badge)

	if has_perks:
		var details_button: Button = Button.new()
		details_button.text = "Details"
		details_button.pressed.connect(_open_detail.bind(skill_name))
		head.add_child(details_button)

	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(1, xp_to_next)
	bar.value = xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(bar)

	var xp_label: Label = Label.new()
	xp_label.text = "%d / %d xp" % [xp, xp_to_next]
	vbox.add_child(xp_label)

	return panel


# --- Detail overlay (bonuses + perk picker) ---

func _open_detail(skill_name: String) -> void:
	_open_skill = skill_name
	if _overlay == null:
		_build_overlay()
	_rebuild_detail()
	_overlay.show()


## Builds the modal once: a full-rect blocker + dimmer with a centered, content-sized
## card. Added to the menu root so it covers the tabs and close button too.
func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Clicking the dimmed area (outside the card) closes the detail.
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_detail())
	_overlay.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Let clicks on the empty area fall through to the dimmer (to close).
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	var card_margin: MarginContainer = MarginContainer.new()
	card_margin.add_theme_constant_override(&"margin_left", 14)
	card_margin.add_theme_constant_override(&"margin_right", 14)
	card_margin.add_theme_constant_override(&"margin_top", 12)
	card_margin.add_theme_constant_override(&"margin_bottom", 12)
	card.add_child(card_margin)

	_detail_root = VBoxContainer.new()
	_detail_root.add_theme_constant_override(&"separation", 6)
	card_margin.add_child(_detail_root)

	# Cover the whole menu (tabs + close button), not just this tab's rect.
	var host: Node = owner if owner else self
	host.add_child(_overlay)


func _close_detail() -> void:
	_open_skill = ""
	if _overlay:
		_overlay.hide()


func _rebuild_detail() -> void:
	if _detail_root == null or not _skills.has(_open_skill):
		return
	for child in _detail_root.get_children():
		child.queue_free()

	var info: Dictionary = _skills[_open_skill]

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	_detail_root.add_child(header)

	var title: Label = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "%s — Lv %d" % [_open_skill.capitalize(), int(info.get("level", 1))]
	header.add_child(title)

	var close_button: Button = Button.new()
	close_button.text = "✕"
	close_button.pressed.connect(_close_detail)
	header.add_child(close_button)

	for perk_line: String in info.get("perks", PackedStringArray()):
		var perk_label: Label = Label.new()
		perk_label.text = "• " + perk_line
		perk_label.add_theme_color_override(&"font_color", Color(0.6, 0.85, 1.0))
		_detail_root.add_child(perk_label)

	if info.has("choices"):
		var points: int = int(info.get("points", 0))
		var points_label: Label = Label.new()
		points_label.text = "Perk points: %d" % points
		_detail_root.add_child(points_label)
		for choice: Dictionary in info["choices"]:
			_detail_root.add_child(_make_perk_choice(_open_skill, choice, points))


func _make_perk_choice(skill_name: String, choice: Dictionary, points: int) -> HBoxContainer:
	var rank: int = int(choice.get("rank", 0))
	var max_rank: int = int(choice.get("max_rank", 0))

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 8)

	var label: Label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s (%d/%d)" % [String(choice.get("name", "")), rank, max_rank]
	hbox.add_child(label)

	var button: Button = Button.new()
	button.text = "+"
	button.custom_minimum_size = Vector2(36, 36)
	button.disabled = points <= 0 or rank >= max_rank
	button.pressed.connect(_on_perk_pressed.bind(skill_name, String(choice.get("id", ""))))
	hbox.add_child(button)

	return hbox


func _on_perk_pressed(skill_name: String, perk_id: String) -> void:
	Client.request_data(
		&"skill.perk.choose",
		func(_data: Dictionary): _refresh(),
		{"skill": skill_name, "perk": perk_id},
		InstanceClient.current.name
	)
