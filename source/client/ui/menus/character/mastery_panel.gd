extends VBoxContainer
## Weapon Mastery HUB (Character > Mastery tab): a split view —
##   - Left:  one row per weapon category that has a mastery tree.
##   - Right: the selected category's summary (level + XP, points available, its
##            current Q/E loadout) and an "Open tree" button.
##
## Learning nodes and equipping abilities happen in the full-screen mastery_tree
## menu (opened by "Open tree"); this hub is the overview + launch point, so it
## stays readable on a phone. Tree CONTENT comes from MasteryService.trees()
## (common/ data the client already has); only per-player state (level, xp,
## points, loadout) is fetched via mastery.get when the tab is shown.

## Input labels per special-slot position — purely cosmetic (binds live in the
## InputMap); mirrors the tree menu's SLOT_KEYS.
const SLOT_KEYS: Array[String] = ["Q", "E"]

## Per-category server state: category (String) -> {level, xp, xp_to_next,
## points, spent: Array, loadout: Array}.
var _state: Dictionary
## The wielded weapon's {category, capacity} — the power budget the loadout
## fits within. Empty category = no (mastery) weapon equipped.
var _wielded: Dictionary = {}
var _selected: String = ""

var _list: VBoxContainer
var _summary: VBoxContainer
var _row_buttons: Dictionary[String, Button]


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_build_layout()
	_refresh()


func _build_layout() -> void:
	var split: HBoxContainer = HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", 12)
	add_child(split)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(220, 0)
	_list.add_theme_constant_override(&"separation", 6)
	split.add_child(_list)

	_summary = VBoxContainer.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_constant_override(&"separation", 8)
	split.add_child(_summary)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree() or InstanceClient.current == null:
		return
	Client.request_data(&"mastery.get", _on_mastery_received, {}, InstanceClient.current.name)


func _on_mastery_received(data: Dictionary) -> void:
	_state = data.get("masteries", {})
	_wielded = data.get("wielded", {})
	if _selected == "" or MasteryService.tree_for(StringName(_selected)) == null:
		_selected = ""
		for category: StringName in MasteryService.trees():
			_selected = String(category)
			break
	_rebuild_list()
	_rebuild_summary()


# ---------------------------------------------------------------------------
# Left — category list
# ---------------------------------------------------------------------------

func _rebuild_list() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_row_buttons.clear()

	var header: Label = Label.new()
	header.text = "Weapon Mastery"
	header.add_theme_font_size_override(&"font_size", 14)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.55))
	_list.add_child(header)

	if MasteryService.trees().is_empty():
		var hint: Label = Label.new()
		hint.text = "No mastery trees exist yet."
		hint.modulate.a = 0.55
		_list.add_child(hint)
		return

	for category: StringName in MasteryService.trees():
		var tree: MasteryTreeResource = MasteryService.trees()[category]
		var info: Dictionary = _state.get(String(category), {})
		var level: int = int(info.get("level", 0))
		var points: int = int(info.get("points", 0))
		var display: String = tree.display_name if not tree.display_name.is_empty() else String(category).capitalize()

		var button: Button = Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_pressed = (String(category) == _selected)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 42)
		var badge: String = "   ●%d" % points if points > 0 else ""
		button.text = ("%s · Lv %d%s" % [display, level, badge]) if level > 0 else ("%s · unpracticed" % display)
		if points > 0:
			button.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5))
		button.pressed.connect(_select_category.bind(String(category)))
		_list.add_child(button)
		_row_buttons[String(category)] = button


func _select_category(category: String) -> void:
	_selected = category
	for key: String in _row_buttons:
		_row_buttons[key].button_pressed = (key == _selected)
	_rebuild_summary()


# ---------------------------------------------------------------------------
# Right — selected category summary
# ---------------------------------------------------------------------------

func _rebuild_summary() -> void:
	for child: Node in _summary.get_children():
		child.queue_free()

	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_selected))
	if tree == null:
		var empty: Label = Label.new()
		empty.text = "Select a weapon to view its mastery."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.55
		_summary.add_child(empty)
		return

	var info: Dictionary = _state.get(_selected, {})
	var level: int = int(info.get("level", 0))
	var points: int = int(info.get("points", 0))
	var display: String = tree.display_name if not tree.display_name.is_empty() else _selected.capitalize()

	var title: Label = Label.new()
	title.text = ("%s Mastery · Lv %d" % [display, level]) if level > 0 else ("%s Mastery" % display)
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	_summary.add_child(title)

	if level <= 0:
		var hint: Label = Label.new()
		hint.text = "Defeat an enemy wielding a %s to begin its mastery." % display.to_lower()
		hint.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_summary.add_child(hint)
	else:
		var bar: ProgressBar = ProgressBar.new()
		bar.theme_type_variation = &"XPBar"
		bar.min_value = 0
		bar.max_value = maxi(1, int(info.get("xp_to_next", 1)))
		bar.value = int(info.get("xp", 0))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 16)
		_summary.add_child(bar)

		var status: Label = Label.new()
		var at_cap: bool = level >= int(PlayerResource.MASTERY_LEVEL_CAP)
		var xp_text: String = "Max level" if at_cap else "%d / %d XP" % [int(info.get("xp", 0)), int(info.get("xp_to_next", 1))]
		status.text = "%s    ·    %d point%s available" % [xp_text, points, "" if points == 1 else "s"]
		status.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5) if points > 0 else Color(0.7, 0.72, 0.78))
		status.add_theme_font_size_override(&"font_size", 12)
		_summary.add_child(status)

	# Loadout — read-only Q/E summary; equipping happens in the tree.
	var loadout_label: Label = Label.new()
	loadout_label.text = "Loadout"
	loadout_label.add_theme_color_override(&"font_color", Color(0.8, 0.82, 0.9))
	loadout_label.add_theme_font_size_override(&"font_size", 13)
	_summary.add_child(loadout_label)
	_summary.add_child(_make_loadout_strip(info))

	# Power line — what the loadout demands vs the wielded weapon's capacity.
	var cap: int = _wielded_capacity()
	var used: int = _loadout_power_used(info.get("loadout", []), tree)
	if cap >= 0 or used > 0:
		var power: Label = Label.new()
		power.add_theme_font_size_override(&"font_size", 12)
		power.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if cap < 0:
			power.text = "Loadout power: %d  (equip a %s to channel it)" % [used, display.to_lower()]
			power.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
		elif used > cap:
			power.text = "Weapon power: %d / %d. Over capacity, the heaviest ability won't channel." % [used, cap]
			power.add_theme_color_override(&"font_color", Color(1.0, 0.55, 0.4))
		else:
			power.text = "Weapon power: %d / %d used" % [used, cap]
			power.add_theme_color_override(&"font_color", Color(0.7, 0.85, 1.0))
		_summary.add_child(power)

	# Spacer + Open-tree button pinned bottom-right.
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_child(spacer)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	_summary.add_child(actions)

	var open_tree: Button = Button.new()
	open_tree.text = "Open tree"
	open_tree.custom_minimum_size = Vector2(150, 42)
	open_tree.pressed.connect(_open_tree)
	actions.add_child(open_tree)


func _open_tree() -> void:
	ClientState.open_menu_requested.emit(&"mastery_tree", _selected)


## The category's two special slots (Q / E) at a glance — read-only here.
func _make_loadout_strip(info: Dictionary) -> Control:
	var loadout: Array = info.get("loadout", [])
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	for i: int in SLOT_KEYS.size():
		var node_id: String = str(loadout[i]) if i < loadout.size() else ""
		row.add_child(_make_loadout_chip(SLOT_KEYS[i], node_id))
	return row


## One loadout slot chip: the input key + the equipped ability's name (or Empty).
func _make_loadout_chip(key: String, node_id: String) -> Control:
	var filled: bool = not node_id.is_empty()
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.10, 0.13, 0.85)
	box.set_corner_radius_all(4)
	box.set_border_width_all(1)
	box.border_color = Color(0.5, 0.85, 0.55, 0.7) if filled else Color(0.28, 0.30, 0.38, 0.5)
	box.set_content_margin_all(8)
	box.content_margin_left = 10
	box.content_margin_right = 10
	panel.add_theme_stylebox_override(&"panel", box)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 8)
	panel.add_child(hbox)

	var key_label: Label = Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override(&"font_size", 16)
	key_label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.55))
	hbox.add_child(key_label)

	var name_label: Label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text = _node_display_name(node_id) if filled else "Empty"
	if not filled:
		name_label.add_theme_color_override(&"font_color", Color(0.6, 0.62, 0.7))
	hbox.add_child(name_label)
	return panel


func _node_display_name(node_id: String) -> String:
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_selected))
	if tree != null:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node != null:
			return node.node_name
	return node_id


## The wielded weapon's power capacity IF it matches the viewed category, else -1.
func _wielded_capacity() -> int:
	if str(_wielded.get("category", "")) == _selected:
		return int(_wielded.get("capacity", 0))
	return -1


## Total power the loadout picks consume (sum of their tiers; "" holes skipped).
func _loadout_power_used(picks: Array, tree: MasteryTreeResource) -> int:
	if tree == null:
		return 0
	var total: int = 0
	for pick: Variant in picks:
		var id: String = str(pick)
		if id.is_empty():
			continue
		var node: MasteryNode = tree.get_node_by_id(StringName(id))
		if node != null:
			total += node.tier
	return total
