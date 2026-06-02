extends VBoxContainer
## Jobs / Professions panel — split-view layout (Wakfu-style):
##   - Left:  scrollable list of jobs grouped by Gathering / Crafting. The
##            whole row is one toggle button — no separate "Details" click.
##   - Right: scrollable details for the selected job (current XP, current
##            bonuses, perk picker with an inline "+X% effect per rank"
##            description so players can plan without spending to discover).
##
## Layout is built programmatically inside %SkillList so the scene file
## stays minimal and the script owns the structural decisions.

@onready var skill_list: VBoxContainer = %SkillList

var _skills: Dictionary
var _selected: String = ""

# Layout nodes built once in _build_layout, then cleared/refilled on data refreshes.
var _row_container: VBoxContainer       # left column content
var _details_root: VBoxContainer        # right column content
## skill_slug → its row Button so we can keep the toggle state visually
## in sync with [member _selected].
var _row_buttons: Dictionary[String, Button]


func _ready() -> void:
	# A successful gather grants XP — re-fetch so the right panel reflects
	# the new value (also picks up newly unlocked perk points).
	ClientState.gather_succeeded.connect(func(_r): _refresh())
	visibility_changed.connect(_on_visibility_changed)
	_build_layout()
	_refresh()


# ---------------------------------------------------------------------------
# Static layout — one HBox with two ScrollContainers. Built once in _ready,
# never rebuilt; only the inner row + detail content gets re-populated.
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	for child in skill_list.get_children():
		child.queue_free()

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 10)
	skill_list.add_child(hbox)

	# Left: job list. Fixed-width-ish column on the left (Wakfu-feel).
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.7
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(left_scroll)

	_row_container = VBoxContainer.new()
	_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_container.add_theme_constant_override(&"separation", 4)
	left_scroll.add_child(_row_container)

	# Right: details. Wider so XP bar + perk descriptions have room.
	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_stretch_ratio = 1.3
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(right_scroll)

	_details_root = VBoxContainer.new()
	_details_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_root.add_theme_constant_override(&"separation", 8)
	right_scroll.add_child(_details_root)


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
	# Default selection: keep the previous one if it's still around, else
	# fall back to the first job in the list so the right panel is never
	# empty when the player opens the tab.
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

	# Bucket by category (Gathering above Crafting), sorted within each
	# bucket by the registry's declared order.
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

	# Defensive: render any uncategorised jobs at the bottom (a typo in
	# a JobPerks.category field shouldn't make a job invisible).
	for cat in buckets:
		if cat in category_order or cat == "":
			continue
		_row_container.add_child(_make_section_header(cat.capitalize()))
		for entry: Array in buckets[cat]:
			_add_row(entry[0], entry[1])


func _make_section_header(label_text: String) -> Label:
	var header: Label = Label.new()
	header.text = label_text
	header.add_theme_font_size_override(&"font_size", 14)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	return header


func _add_row(skill_name: String, info: Dictionary) -> void:
	var skill_level: int = int(info.get("level", 1))
	var points: int = int(info.get("points", 0))
	var display: String = str(info.get("display_name", skill_name.capitalize()))

	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Toggle mode so the selected row stays visually distinct (Godot's
	# Button has a "pressed" style that reads as a checked state).
	button.toggle_mode = true
	button.button_pressed = (skill_name == _selected)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)

	# Render the unspent-perk-point badge inline in the label — easier than
	# stacking a child label on a Button, and reads at a glance.
	var badge: String = "   ●%d" % points if points > 0 else ""
	button.text = "%s — Lv %d%s" % [display, skill_level, badge]

	# Highlight gold-tone when a point is unspent so the eye is drawn there.
	if points > 0:
		button.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5))

	button.pressed.connect(_select_job.bind(skill_name))
	_row_container.add_child(button)
	_row_buttons[skill_name] = button


func _select_job(skill_name: String) -> void:
	_selected = skill_name
	# Toggle every row to match — Button.toggle_mode keeps state per-button
	# so we have to walk them all on every selection.
	for sn in _row_buttons:
		var btn: Button = _row_buttons[sn]
		btn.button_pressed = (sn == _selected)
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

	# --- Static header (kept above tabs so it's always in view) ---
	var title: Label = Label.new()
	title.text = "%s — Lv %d" % [display, skill_level]
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_root.add_child(title)

	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(1, xp_to_next)
	bar.value = xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	_details_root.add_child(bar)

	var xp_label: Label = Label.new()
	xp_label.text = "%d / %d XP" % [xp, xp_to_next]
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
	_details_root.add_child(xp_label)

	# --- Tabs: Bonuses / Perks / Sources? / Recipes? ---
	# Sources and Recipes are conditional — only show when the JobPerks
	# resource has non-empty lists. Avoids dead "no recipes" empty tabs
	# on gathering jobs (and the reverse on crafting jobs).
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 200)
	# Match the outer character-menu tab bar's slim height so the two rows of
	# tabs read as a coherent stack instead of two different design systems.
	tabs.add_theme_font_size_override(&"font_size", 12)
	tabs.add_theme_stylebox_override(&"tab_selected", _slim_tab_style(Color(0.18, 0.22, 0.36, 1.0)))
	tabs.add_theme_stylebox_override(&"tab_unselected", _slim_tab_style(Color(0.1, 0.12, 0.18, 1.0)))
	_details_root.add_child(tabs)

	tabs.add_child(_build_bonuses_tab(info))
	if info.has("choices"):
		tabs.add_child(_build_perks_tab(info))
	var sources: Array = info.get("source_slugs", [])
	if not sources.is_empty():
		tabs.add_child(_build_slug_list_tab("Sources", sources, "These are the materials you can gather for this profession."))
	var recipes: Array = info.get("recipe_slugs", [])
	if not recipes.is_empty():
		tabs.add_child(_build_slug_list_tab("Recipes", recipes, "Items this profession can craft."))


# ---------------------------------------------------------------------------
# Tab builders — each returns a Control whose `name` becomes the tab label.
# ---------------------------------------------------------------------------

func _build_bonuses_tab(info: Dictionary) -> Control:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "Bonuses"
	vbox.add_theme_constant_override(&"separation", 4)

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

	return vbox


func _build_perks_tab(info: Dictionary) -> Control:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "Perks"
	vbox.add_theme_constant_override(&"separation", 4)

	var points: int = int(info.get("points", 0))
	var points_label: Label = Label.new()
	points_label.text = "%d point%s available" % [points, "" if points == 1 else "s"]
	points_label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5) if points > 0 else Color(0.7, 0.72, 0.78))
	vbox.add_child(points_label)

	for choice in info.get("choices", []):
		vbox.add_child(_make_perk_row(_selected, choice, points))

	return vbox


## Generic tab for a list of item slugs — Sources or Recipes. Slug
## resolution to real item names/icons would happen here once we have a
## slug→Item registry exposed to the client. For v1 we show the slug
## title-cased so designers can sanity-check the JobPerks .tres data.
func _build_slug_list_tab(tab_name: String, slugs: Array, hint: String) -> Control:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = tab_name
	vbox.add_theme_constant_override(&"separation", 4)

	var hint_label: Label = Label.new()
	hint_label.text = hint
	hint_label.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
	hint_label.add_theme_font_size_override(&"font_size", 11)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint_label)

	vbox.add_child(HSeparator.new())

	for slug in slugs:
		var row: PanelContainer = PanelContainer.new()
		var margin: MarginContainer = MarginContainer.new()
		margin.add_theme_constant_override(&"margin_left", 8)
		margin.add_theme_constant_override(&"margin_right", 8)
		margin.add_theme_constant_override(&"margin_top", 4)
		margin.add_theme_constant_override(&"margin_bottom", 4)
		row.add_child(margin)

		var label: Label = Label.new()
		# slug_with_underscores → "Slug With Underscores". Title-case until
		# we wire slug→Item lookup for real item_name + icon.
		label.text = _slug_to_title(str(slug))
		margin.add_child(label)

		vbox.add_child(row)

	return vbox


## Slim tab StyleBox — small vertical content margin so the inner tab bar
## stays shorter than Godot's chunky default. Wide horizontal margin keeps
## the tabs comfortably tappable on mobile.
func _slim_tab_style(bg: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	return box


## "copper_ore" → "Copper Ore". Cheap title-casing for the slug placeholder.
func _slug_to_title(slug: String) -> String:
	var parts: PackedStringArray = slug.split("_")
	var out: PackedStringArray = PackedStringArray()
	for p: String in parts:
		if p.is_empty():
			continue
		out.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(out)


# ---------------------------------------------------------------------------
# One perk row: name + (rank/max), inline "what one rank gives" description,
# and a [+] spend button.
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
	margin.add_theme_constant_override(&"margin_top", 4)
	margin.add_theme_constant_override(&"margin_bottom", 4)
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

	# The "what one rank gives" hint — derived from the server-supplied
	# effect + per_rank, so future jobs / effects show up automatically.
	var desc_label: Label = Label.new()
	desc_label.text = _describe_perk(choice)
	desc_label.add_theme_color_override(&"font_color", Color(0.62, 0.74, 0.86))
	desc_label.add_theme_font_size_override(&"font_size", 11)
	name_vbox.add_child(desc_label)

	var btn: Button = Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(36, 36)
	btn.disabled = available_points <= 0 or rank >= max_rank
	btn.pressed.connect(_on_perk_pressed.bind(skill_name, perk_id))
	hbox.add_child(btn)

	return panel


## Builds the inline "X per rank" hint from the choice's effect + per_rank
## fields. Generic — when a new effect kind is added to JobPerks, list it
## here and every job that uses it gets a description for free.
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
