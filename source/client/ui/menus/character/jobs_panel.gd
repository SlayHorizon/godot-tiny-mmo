extends VBoxContainer
## Jobs / Professions panel — split-view layout (Wakfu-style):
##   - Left:  scrollable list of jobs grouped by Gathering / Crafting. The
##            whole row is one toggle button.
##   - Right: details for the selected job. A fixed header (title + XP bar)
##            sits above a row of section toggles (Bonuses / Perks / Sources /
##            Recipes); the active section fills the remaining space and owns
##            the ONLY scroll in the column.
##
## The right column deliberately has no outer ScrollContainer — an earlier
## version nested the per-section scroll inside an outer scroll, and the inner
## one collapsed to ~0 height (a ScrollContainer's min height is 0), which is
## why the Sources/Recipes content rendered blank. One scroll per region.
##
## Sources / Recipes read JobRegistry directly (JobPerks is preloaded in
## common/, so the client already has the rich Item refs + level gates) — no
## server roundtrip needed for that static content.

@onready var skill_list: VBoxContainer = %SkillList

var _skills: Dictionary
var _selected: String = ""
## Remembered active section index so re-fetches (after a gather/level-up)
## don't snap the player back to the Bonuses tab mid-read.
var _section_index: int

var _row_container: VBoxContainer
var _details_root: VBoxContainer
var _row_buttons: Dictionary[String, Button]


func _ready() -> void:
	ClientState.gather_succeeded.connect(func(_r): _refresh())
	visibility_changed.connect(_on_visibility_changed)
	_build_layout()
	_refresh()


# ---------------------------------------------------------------------------
# Static layout — one HBox, left list scroll + right details column.
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	for child in skill_list.get_children():
		child.queue_free()

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 12)
	skill_list.add_child(hbox)

	# Left: job list.
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.75
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(left_scroll)

	_row_container = VBoxContainer.new()
	_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_container.add_theme_constant_override(&"separation", 4)
	left_scroll.add_child(_row_container)

	# Right: details. NOT wrapped in a ScrollContainer — sections scroll
	# themselves so the header (title + XP) stays pinned.
	_details_root = VBoxContainer.new()
	_details_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_root.size_flags_stretch_ratio = 1.4
	_details_root.add_theme_constant_override(&"separation", 8)
	hbox.add_child(_details_root)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	Client.request_data(&"skills.get", _on_skills_received, {}, InstanceClient.current.name)


func _on_skills_received(data: Dictionary) -> void:
	_skills = data.get("skills", {})
	_rebuild_rows()
	if _selected == "" or not _skills.has(_selected):
		_selected = ""
		for skill_name in _skills:
			_selected = String(skill_name)
			break
	_rebuild_details()


# ---------------------------------------------------------------------------
# Left column — job list
# ---------------------------------------------------------------------------

func _rebuild_rows() -> void:
	for child in _row_container.get_children():
		child.queue_free()
	_row_buttons.clear()

	var buckets: Dictionary = {}
	for skill_name in _skills:
		var info: Dictionary = _skills[skill_name]
		var category: String = str(info.get("category", ""))
		if not buckets.has(category):
			buckets[category] = []
		buckets[category].append([String(skill_name), info])

	for cat in buckets:
		(buckets[cat] as Array).sort_custom(func(a, b):
			return int(a[1].get("order", 0)) < int(b[1].get("order", 0)))

	var category_order: PackedStringArray = PackedStringArray(["gathering", "crafting"])
	for cat in category_order:
		if not buckets.has(cat):
			continue
		_row_container.add_child(_make_section_header(cat.capitalize()))
		for entry: Array in buckets[cat]:
			_add_row(entry[0], entry[1])

	for cat in buckets:
		if cat in category_order or cat == "":
			continue
		_row_container.add_child(_make_section_header(cat.capitalize()))
		for entry: Array in buckets[cat]:
			_add_row(entry[0], entry[1])

	# Touch/mouse drag-to-scroll for the job list.
	DragScroll.enable(_row_container.get_parent() as ScrollContainer)


func _make_section_header(label_text: String) -> Label:
	var header: Label = Label.new()
	header.text = label_text
	header.add_theme_font_size_override(&"font_size", 13)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	return header


func _add_row(skill_name: String, info: Dictionary) -> void:
	var skill_level: int = int(info.get("level", 1))
	var points: int = int(info.get("points", 0))
	var display: String = str(info.get("display_name", skill_name.capitalize()))

	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_pressed = (skill_name == _selected)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 40)

	var badge: String = "   ●%d" % points if points > 0 else ""
	button.text = "%s — Lv %d%s" % [display, skill_level, badge]
	if points > 0:
		button.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5))

	button.pressed.connect(_select_job.bind(skill_name))
	_row_container.add_child(button)
	_row_buttons[skill_name] = button


func _select_job(skill_name: String) -> void:
	_selected = skill_name
	_section_index = 0
	for sn in _row_buttons:
		_row_buttons[sn].button_pressed = (sn == _selected)
	_rebuild_details()


# ---------------------------------------------------------------------------
# Right column — details for [member _selected]
# ---------------------------------------------------------------------------

func _rebuild_details() -> void:
	for child in _details_root.get_children():
		child.queue_free()

	if _selected == "" or not _skills.has(_selected):
		var empty: Label = Label.new()
		empty.text = "Select a profession on the left."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.55
		_details_root.add_child(empty)
		return

	var info: Dictionary = _skills[_selected]
	var display: String = str(info.get("display_name", _selected.capitalize()))
	var skill_level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var xp_to_next: int = int(info.get("xp_to_next", 1))

	# --- Pinned header ---
	var title: Label = Label.new()
	title.text = "%s — Lv %d" % [display, skill_level]
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_root.add_child(title)

	var bar: ProgressBar = ProgressBar.new()
	bar.theme_type_variation = &"XPBar"
	bar.min_value = 0
	bar.max_value = maxi(1, xp_to_next)
	bar.value = xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	_details_root.add_child(bar)

	var xp_label: Label = Label.new()
	xp_label.text = "%d / %d XP" % [xp, xp_to_next]
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
	xp_label.add_theme_font_size_override(&"font_size", 12)
	_details_root.add_child(xp_label)

	# --- Sections ---
	var jp: JobPerks = JobRegistry.perks_for(StringName(_selected))

	var specs: Array = []  # [[name, content_control], ...]
	specs.append(["Bonuses", _build_bonuses_section(info)])
	if info.has("choices"):
		specs.append(["Perks", _build_perks_section(info)])
	if jp != null and not jp.source_items.is_empty():
		specs.append(["Sources", _build_item_list_section(
			jp.source_items, jp.source_levels,
			"Gather these to feed this profession's XP.")])
	if jp != null and not jp.recipe_items.is_empty():
		specs.append(["Recipes", _build_item_list_section(
			jp.recipe_items, jp.recipe_levels,
			"Items this profession can craft.")])

	_section_index = clampi(_section_index, 0, specs.size() - 1)

	var section_bar: HBoxContainer = HBoxContainer.new()
	section_bar.add_theme_constant_override(&"separation", 4)
	_details_root.add_child(section_bar)

	# Content area fills the rest of the column — gives the active section's
	# ScrollContainer a concrete height to scroll within.
	var content_area: PanelContainer = PanelContainer.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_root.add_child(content_area)

	var buttons: Array[Button] = []
	var contents: Array[Control] = []
	for i in specs.size():
		var spec: Array = specs[i]
		var btn: Button = Button.new()
		btn.text = spec[0]
		btn.theme_type_variation = &"SectionTab"
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.button_pressed = (i == _section_index)
		section_bar.add_child(btn)
		buttons.append(btn)

		var content: Control = spec[1]
		content.visible = (i == _section_index)
		content_area.add_child(content)
		contents.append(content)

		btn.pressed.connect(_select_section.bind(i, buttons, contents))


func _select_section(idx: int, buttons: Array[Button], contents: Array[Control]) -> void:
	_section_index = idx
	for i in buttons.size():
		buttons[i].button_pressed = (i == idx)
	for i in contents.size():
		contents[i].visible = (i == idx)


# ---------------------------------------------------------------------------
# Section builders — each fills the content area; lists own their scroll.
# ---------------------------------------------------------------------------

func _build_bonuses_section(info: Dictionary) -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override(&"separation", 6)
	scroll.add_child(vbox)

	for line in info.get("perks", []):
		var bullet: Label = Label.new()
		bullet.text = "• " + str(line)
		bullet.add_theme_color_override(&"font_color", Color(0.6, 0.85, 1.0))
		vbox.add_child(bullet)

	if vbox.get_child_count() == 0:
		var hint: Label = Label.new()
		hint.text = "Train this profession to unlock baseline bonuses."
		hint.modulate.a = 0.55
		vbox.add_child(hint)

	return scroll


func _build_perks_section(info: Dictionary) -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override(&"separation", 6)
	scroll.add_child(vbox)

	var points: int = int(info.get("points", 0))
	var points_label: Label = Label.new()
	points_label.text = "%d point%s available" % [points, "" if points == 1 else "s"]
	points_label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5) if points > 0 else Color(0.7, 0.72, 0.78))
	vbox.add_child(points_label)

	for choice in info.get("choices", []):
		vbox.add_child(_make_perk_row(_selected, choice, points))

	return scroll


## Rich-row list — one row per item with icon, name, and the level it's gated
## behind. Used for Sources (ores to gather) and Recipes (craftable outputs).
func _build_item_list_section(items: Array[Item], levels: Array[int], hint: String) -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override(&"separation", 4)
	scroll.add_child(vbox)

	var hint_label: Label = Label.new()
	hint_label.text = hint
	hint_label.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
	hint_label.add_theme_font_size_override(&"font_size", 11)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint_label)

	vbox.add_child(HSeparator.new())

	for i in items.size():
		var item: Item = items[i]
		if item == null:
			continue
		var required_level: int = levels[i] if i < levels.size() else 0
		vbox.add_child(_build_item_row(item, required_level))

	return scroll


func _build_item_row(item: Item, required_level: int) -> Control:
	var row: PanelContainer = PanelContainer.new()
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 8)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_top", 4)
	margin.add_theme_constant_override(&"margin_bottom", 4)
	row.add_child(margin)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 8)
	margin.add_child(hbox)

	var icon: TextureRect = TextureRect.new()
	icon.texture = item.item_icon
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(icon)

	var name_label: Label = Label.new()
	name_label.text = String(item.item_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_label)

	if required_level > 1:
		var lvl: Label = Label.new()
		lvl.text = "Lv %d" % required_level
		lvl.add_theme_color_override(&"font_color", Color(0.8, 0.85, 1.0))
		lvl.add_theme_font_size_override(&"font_size", 12)
		lvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(lvl)

	return row


# ---------------------------------------------------------------------------
# One perk row: name + (rank/max), inline "per rank" hint, and a [+] button.
# ---------------------------------------------------------------------------

func _make_perk_row(skill_name: String, choice: Dictionary, available_points: int) -> Control:
	var rank: int = int(choice.get("rank", 0))
	var max_rank: int = int(choice.get("max_rank", 0))
	var perk_id: String = str(choice.get("id", ""))
	var perk_name: String = str(choice.get("name", ""))

	var panel: PanelContainer = PanelContainer.new()

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 8)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_top", 5)
	margin.add_theme_constant_override(&"margin_bottom", 5)
	panel.add_child(margin)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 8)
	margin.add_child(hbox)

	var name_vbox: VBoxContainer = VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vbox.add_theme_constant_override(&"separation", 0)
	hbox.add_child(name_vbox)

	var name_label: Label = Label.new()
	name_label.text = "%s  (%d/%d)" % [perk_name, rank, max_rank]
	name_vbox.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.text = _describe_perk(choice)
	desc_label.add_theme_color_override(&"font_color", Color(0.62, 0.74, 0.86))
	desc_label.add_theme_font_size_override(&"font_size", 11)
	name_vbox.add_child(desc_label)

	var btn: Button = Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(38, 38)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = available_points <= 0 or rank >= max_rank
	btn.pressed.connect(_on_perk_pressed.bind(skill_name, perk_id))
	hbox.add_child(btn)

	return panel


func _describe_perk(choice: Dictionary) -> String:
	var effect: String = str(choice.get("effect", ""))
	var per_rank: float = float(choice.get("per_rank", 0.0))
	var pct: int = roundi(per_rank * 100.0)
	match effect:
		"xp":
			return "+%d%% XP per rank" % pct
		"cooldown":
			return "+%d%% gather speed per rank" % pct
		"bonus_yield":
			return "+%d%% bonus yield chance per rank" % pct
		"refund":
			return "+%d%% material refund chance per rank" % pct
		"extra_item":
			return "+%d%% extra item chance per rank" % pct
		_:
			return ""


func _on_perk_pressed(skill_name: String, perk_id: String) -> void:
	Client.request_data(
		&"skill.perk.choose",
		func(_d): _refresh(),
		{"skill": skill_name, "perk": perk_id},
		InstanceClient.current.name
	)
