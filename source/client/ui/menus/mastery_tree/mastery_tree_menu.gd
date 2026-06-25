extends MenuShell
## Full-screen weapon-mastery skill tree — the "Open tree" target from the Mastery
## hub (Character > Mastery tab). Shows ONE domain (weapon category): its three
## branches (Domination / Resolve / Inspiration) as columns of icon tiles, upgrade
## chains linked by connectors, with a pinned detail panel for the selected node.
##
## Tree CONTENT comes from MasteryService.trees() (common/ data the client already
## holds). Per-player state (level, points, owned nodes, loadout) is fetched via
## mastery.get; learn / equip / respec are server-validated (mastery.spend /
## mastery.loadout / mastery.respec) — this menu just re-fetches and rebuilds.

const BRANCHES: Array[StringName] = [&"domination", &"resolve", &"inspiration"]
## Input labels per special-slot position (slot 1 = player_special, 2 = _special_2).
const SLOT_KEYS: Array[String] = ["Q", "E"]
const BRANCH_COLORS: Dictionary[StringName, Color] = {
	&"domination": Color(1.0, 0.55, 0.42),
	&"resolve": Color(0.55, 0.75, 1.0),
	&"inspiration": Color(0.65, 0.95, 0.72),
}
const BRANCH_SUBTITLES: Dictionary[StringName, String] = {
	&"domination": "Power & Pressure",
	&"resolve": "Defense & Durability",
	&"inspiration": "Support & Mobility",
}
const TILE_SIZE: Vector2 = Vector2(54, 54)
## Placeholder lock art path (artist drop-in later). Loaded at runtime, NOT
## preloaded, so an un-imported / missing test asset degrades to initials instead
## of breaking the whole menu at parse time. Real node icons come from
## MasteryNode.icon / AbilityResource.icon.
const LOCKED_ICON_PATH: String = "res://assets/sprites/gui/test/locked_icon.png"

const COLOR_OWNED: Color = Color(0.5, 0.85, 0.55)
const COLOR_LEARN: Color = Color(0.96, 0.74, 0.16)
const COLOR_EQUIP: Color = Color(0.30, 0.55, 0.95)

var _category: String = ""
var _state: Dictionary = {}
var _wielded: Dictionary = {}
var _selected_node: String = ""

var _points_label: Label
var _picker_overlay: Control
var _locked_icon: Texture2D


func _ready() -> void:
	build_shell("Mastery", null, true)
	# Full-screen takeover: make the shell backdrop opaque so the menu we opened
	# FROM (the character window) doesn't bleed through the translucent panels.
	var backdrop: ColorRect = get_child(0) as ColorRect
	if backdrop != null:
		backdrop.color = Color(0.05, 0.06, 0.09, 0.98)
	if ResourceLoader.exists(LOCKED_ICON_PATH):
		_locked_icon = load(LOCKED_ICON_PATH)
	visibility_changed.connect(_on_visibility_changed)
	close_requested.connect(_close_slot_picker)
	# The shell's right-side button reads "Close"; here it's a Back to the hub.
	var back_button: Button = header_right.get_child(0) as Button
	if back_button != null:
		back_button.text = "Back"
	# Points readout in the header centre.
	_points_label = Label.new()
	_points_label.add_theme_color_override(&"font_color", COLOR_LEARN)
	_points_label.add_theme_font_size_override(&"font_size", 14)
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_center.add_child(_points_label)
	# Reset sits left of Back.
	var reset: Button = Button.new()
	reset.text = "Reset points"
	reset.custom_minimum_size = Vector2(0, 34)
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(_on_respec_pressed)
	header_right.add_child(reset)
	header_right.move_child(reset, 0)


## Entry point from HUD.display_menu(&"mastery_tree", category). [param category]
## is the weapon-category string chosen in the hub.
func open(category: String) -> void:
	_category = str(category)
	_selected_node = ""
	_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()
	else:
		_close_slot_picker()


func _refresh() -> void:
	if not is_visible_in_tree() or _category.is_empty() or InstanceClient.current == null:
		return
	Client.request_data(&"mastery.get", _on_mastery_received, {}, InstanceClient.current.name)


func _on_mastery_received(data: Dictionary) -> void:
	_state = data.get("masteries", {})
	_wielded = data.get("wielded", {})
	_rebuild()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for child: Node in content.get_children():
		child.queue_free()

	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_category))
	var info: Dictionary = _state.get(_category, {})
	var level: int = int(info.get("level", 0))
	var points: int = int(info.get("points", 0))
	var display: String = _category.capitalize()
	if tree != null and not tree.display_name.is_empty():
		display = tree.display_name

	set_title("%s Mastery%s" % [display, (" · Lv %d" % level) if level > 0 else ""])
	_points_label.text = ("%d point%s" % [points, "" if points == 1 else "s"]) if points > 0 else ""

	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override(&"separation", 8)
	content.add_child(root_box)

	if tree == null:
		var empty: Label = Label.new()
		empty.text = "This weapon has no mastery tree yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.6
		root_box.add_child(empty)
		return

	# Default selection so the detail panel is never blank.
	if _selected_node.is_empty() or tree.get_node_by_id(StringName(_selected_node)) == null:
		_selected_node = _default_selection(tree)

	var branches_row: HBoxContainer = HBoxContainer.new()
	branches_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branches_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	branches_row.add_theme_constant_override(&"separation", 10)
	root_box.add_child(branches_row)
	for branch: StringName in BRANCHES:
		branches_row.add_child(_make_branch_panel(branch, tree, info))

	root_box.add_child(_make_detail_panel(tree, info))
	root_box.add_child(_make_legend())


## Prefer the first owned ability (what the player most likely wants to manage),
## else the very first node, so opening the tree always lands somewhere useful.
func _default_selection(tree: MasteryTreeResource) -> String:
	var owned: Array = _state.get(_category, {}).get("spent", [])
	for node: MasteryNode in tree.nodes:
		if node.ability != null and owned.has(String(node.id)):
			return String(node.id)
	return String(tree.nodes[0].id) if not tree.nodes.is_empty() else ""


func _make_branch_panel(branch: StringName, tree: MasteryTreeResource, info: Dictionary) -> Control:
	var color: Color = BRANCH_COLORS.get(branch, Color.WHITE)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, 0.06)
	box.set_corner_radius_all(8)
	box.set_border_width_all(1)
	box.border_color = Color(color.r, color.g, color.b, 0.4)
	box.set_content_margin_all(8)
	panel.add_theme_stylebox_override(&"panel", box)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 4)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = String(branch).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override(&"font_color", color)
	title.add_theme_font_size_override(&"font_size", 14)
	vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = BRANCH_SUBTITLES.get(branch, "")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
	subtitle.add_theme_font_size_override(&"font_size", 10)
	vbox.add_child(subtitle)

	# The node area fills the rest of the panel; chain columns sit at the BOTTOM
	# and grow upward (tier 1 on the bottom row), so a tree reads as built from its
	# foundation up. No scroll for now — alpha trees are shallow (<= 4 deep).
	var area: HBoxContainer = HBoxContainer.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.alignment = BoxContainer.ALIGNMENT_CENTER
	area.add_theme_constant_override(&"separation", 12)
	vbox.add_child(area)

	var groups: Array = _chain_groups(branch, tree)
	for group: Array in groups:
		area.add_child(_make_chain_column(group, tree, info, color))
	return panel


## Branch nodes grouped by upgrade chain: each chain (and each standalone node)
## becomes one vertical column, sorted by tier, so chains stack and connect.
func _chain_groups(branch: StringName, tree: MasteryTreeResource) -> Array:
	var groups: Dictionary = {}
	var order: Array[String] = []
	for node: MasteryNode in tree.nodes:
		if node.branch != branch:
			continue
		var root: String = String(MasteryService.chain_root_of(tree, node))
		if not groups.has(root):
			groups[root] = []
			order.append(root)
		(groups[root] as Array).append(node)
	var out: Array = []
	for root: String in order:
		var arr: Array = groups[root]
		arr.sort_custom(func(a: MasteryNode, b: MasteryNode) -> bool: return a.tier < b.tier)
		out.append(arr)
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0].tier) < int(b[0].tier))
	return out


func _make_chain_column(group: Array, tree: MasteryTreeResource, info: Dictionary, color: Color) -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	# Bottom-anchored so every chain's tier-1 tile lands on the same bottom row,
	# however deep the chain runs.
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.add_theme_constant_override(&"separation", 0)
	# Highest tier first (top) down to tier 1 (bottom) — the tree builds upward.
	for i: int in range(group.size() - 1, -1, -1):
		col.add_child(_make_tile(group[i] as MasteryNode, tree, info, color))
		if i > 0:
			var line: ColorRect = ColorRect.new()
			line.color = Color(color.r, color.g, color.b, 0.5)
			line.custom_minimum_size = Vector2(2, 12)
			line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(line)
	return col


func _make_tile(node: MasteryNode, _tree: MasteryTreeResource, info: Dictionary, color: Color) -> Control:
	var owned: bool = (info.get("spent", []) as Array).has(String(node.id))
	var loadout: Array = info.get("loadout", [])
	var slot_index: int = loadout.find(String(node.id))
	var equipped: bool = slot_index >= 0
	var level: int = int(info.get("level", 0))
	var points: int = int(info.get("points", 0))
	var required_level: int = int(MasteryService.TIER_UNLOCK_LEVEL.get(node.tier, 1))
	var owned_set: Dictionary = {}
	for owned_id: Variant in info.get("spent", []):
		owned_set[String(owned_id)] = true
	var prereq_owned: bool = String(node.upgrades).is_empty() or owned_set.has(String(node.upgrades))
	var affordable: bool = not owned and prereq_owned and level >= required_level and points >= node.tier
	var locked: bool = not owned and (not prereq_owned or level < required_level)
	var selected: bool = String(node.id) == _selected_node

	var button: Button = Button.new()
	button.custom_minimum_size = TILE_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = false
	button.tooltip_text = node.node_name

	var border_col: Color = Color(color.r, color.g, color.b, 0.45)
	var border_w: int = 1
	if selected:
		border_col = Color.WHITE
		border_w = 2
	elif equipped:
		border_col = Color(color.r, color.g, color.b, 0.95)
		border_w = 2
	elif affordable:
		border_col = COLOR_LEARN
		border_w = 2
	elif owned:
		border_col = Color(COLOR_OWNED.r, COLOR_OWNED.g, COLOR_OWNED.b, 0.75)

	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.11, 0.14, 1.0)
	box.set_corner_radius_all(6)
	box.set_border_width_all(border_w)
	box.border_color = border_col
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(style_name, box)

	if locked:
		button.modulate.a = 0.5

	var tex: Texture2D = _locked_icon if locked else _node_icon(node)
	if tex != null:
		PixelIcon.mount(button, tex)
	else:
		var initials: Label = Label.new()
		initials.text = _initials(node.node_name)
		initials.add_theme_font_size_override(&"font_size", 18)
		initials.add_theme_color_override(&"font_color", color)
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(initials)
		initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if equipped:
		var key: String = SLOT_KEYS[slot_index] if slot_index < SLOT_KEYS.size() else str(slot_index + 1)
		button.add_child(_badge(key, COLOR_EQUIP, Color.WHITE))
	elif affordable:
		button.add_child(_badge("+", COLOR_LEARN, Color(0.16, 0.12, 0.0)))

	button.pressed.connect(_select_node.bind(String(node.id)))
	return button


func _badge(text: String, bg: Color, fg: Color) -> Control:
	var lab: Label = Label.new()
	lab.text = text
	lab.add_theme_font_size_override(&"font_size", 11)
	lab.add_theme_color_override(&"font_color", fg)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(4)
	b.content_margin_left = 4
	b.content_margin_right = 4
	b.content_margin_top = 1
	b.content_margin_bottom = 1
	lab.add_theme_stylebox_override(&"normal", b)
	# Sit INSIDE the tile's top-right corner (not overhanging) so the glyph is
	# never clipped by the row or panel above.
	lab.anchor_left = 1.0
	lab.anchor_right = 1.0
	lab.offset_left = -19
	lab.offset_top = 2
	lab.offset_right = -3
	lab.offset_bottom = 17
	return lab


func _select_node(node_id: String) -> void:
	_selected_node = node_id
	_rebuild()


# ---------------------------------------------------------------------------
# Detail panel (pinned) — the selected node's full readout + its action.
# ---------------------------------------------------------------------------

func _make_detail_panel(tree: MasteryTreeResource, info: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.10, 0.13, 0.92)
	box.set_corner_radius_all(8)
	box.set_border_width_all(1)
	box.border_color = Color(0.30, 0.32, 0.40, 0.7)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override(&"panel", box)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 12)
	panel.add_child(hbox)

	var node: MasteryNode = tree.get_node_by_id(StringName(_selected_node))
	if node == null:
		var hint: Label = Label.new()
		hint.text = "Select a skill to see what it does."
		hint.modulate.a = 0.6
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(hint)
		return panel

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override(&"separation", 2)
	hbox.add_child(text_box)

	var name_label: Label = Label.new()
	if node.ability != null:
		name_label.text = "%s   ·   Power %d" % [node.node_name, node.tier]
	else:
		name_label.text = "%s   ·   Passive" % node.node_name
	name_label.add_theme_font_size_override(&"font_size", 16)
	name_label.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.78))
	text_box.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.text = node.description
	desc_label.add_theme_color_override(&"font_color", Color(0.74, 0.80, 0.88))
	desc_label.add_theme_font_size_override(&"font_size", 12)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc_label)

	var meta_label: Label = Label.new()
	meta_label.add_theme_font_size_override(&"font_size", 12)
	if node.ability != null:
		var parts: PackedStringArray = PackedStringArray()
		parts.append("%s cooldown" % _fmt_cooldown(node.ability.cooldown))
		if node.ability.mana_cost > 0:
			parts.append("%d mana" % node.ability.mana_cost)
		meta_label.text = "   ·   ".join(parts)
		meta_label.add_theme_color_override(&"font_color", Color(0.85, 0.78, 0.55))
	else:
		meta_label.text = _passive_bonus_text(node)
		meta_label.add_theme_color_override(&"font_color", Color(0.65, 0.9, 0.7))
	text_box.add_child(meta_label)

	hbox.add_child(_make_action_button(node, tree, info))
	return panel


func _make_action_button(node: MasteryNode, _tree: MasteryTreeResource, info: Dictionary) -> Control:
	var owned: bool = (info.get("spent", []) as Array).has(String(node.id))
	var loadout: Array = info.get("loadout", [])
	var slot_index: int = loadout.find(String(node.id))
	var equipped: bool = slot_index >= 0
	var level: int = int(info.get("level", 0))
	var points: int = int(info.get("points", 0))
	var required_level: int = int(MasteryService.TIER_UNLOCK_LEVEL.get(node.tier, 1))
	var owned_set: Dictionary = {}
	for owned_id: Variant in info.get("spent", []):
		owned_set[String(owned_id)] = true
	var prereq_owned: bool = String(node.upgrades).is_empty() or owned_set.has(String(node.upgrades))

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(140, 42)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if not owned:
		if not prereq_owned:
			button.text = "Needs %s" % _node_display_name(String(node.upgrades))
			button.disabled = true
		elif level < required_level:
			button.text = "Reach Lv %d" % required_level
			button.disabled = true
		else:
			button.text = "Learn  (%d)" % node.tier
			button.disabled = points < node.tier
			button.pressed.connect(_on_learn_pressed.bind(String(node.id)))
		return button

	if node.ability == null:
		button.text = "Active"
		button.disabled = true
		return button

	if equipped:
		var key: String = SLOT_KEYS[slot_index] if slot_index < SLOT_KEYS.size() else str(slot_index + 1)
		button.text = "Unequip  (%s)" % key
	else:
		button.text = "Equip  (heavy)" if _too_heavy_for_wielded(node) else "Equip"
	button.pressed.connect(_on_equip_pressed.bind(String(node.id), equipped))
	return button


func _make_legend() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	row.add_child(_legend_item(COLOR_LEARN, "can learn"))
	row.add_child(_legend_item(COLOR_OWNED, "owned"))
	row.add_child(_legend_item(COLOR_EQUIP, "equipped (Q/E)"))
	row.add_child(_legend_item(Color(0.5, 0.52, 0.6), "locked"))
	return row


func _legend_item(color: Color, text: String) -> Control:
	var item: HBoxContainer = HBoxContainer.new()
	item.add_theme_constant_override(&"separation", 5)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.add_child(swatch)
	var lab: Label = Label.new()
	lab.text = text
	lab.add_theme_font_size_override(&"font_size", 10)
	lab.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
	item.add_child(lab)
	return item


# ---------------------------------------------------------------------------
# Actions (server-validated; re-fetch + rebuild on result)
# ---------------------------------------------------------------------------

func _on_learn_pressed(node_id: String) -> void:
	Client.request_data(
		&"mastery.spend",
		func(_d: Dictionary) -> void: _refresh(),
		{"category": _category, "node": node_id},
		InstanceClient.current.name
	)


func _on_equip_pressed(node_id: String, was_equipped: bool) -> void:
	if was_equipped:
		_send_loadout_with(node_id, -1)
		return
	_open_slot_picker(node_id)


## Asks WHICH input slot the ability goes on, via the shared SlotPickerOverlay
## (same picker the inventory hotkey assigner uses). Parented to this menu root
## so it covers the tree and dies with it.
func _open_slot_picker(node_id: String) -> void:
	_close_slot_picker()
	var picks: Array = _current_picks()
	var entries: PackedStringArray = PackedStringArray()
	for i: int in SLOT_KEYS.size():
		var occ_id: String = str(picks[i])
		var occupant: String = "empty"
		if not occ_id.is_empty():
			occupant = "%s (Power %d)" % [_node_display_name(occ_id), _node_power(occ_id)]
		entries.append("Slot %d (%s)  ·  %s" % [i + 1, SLOT_KEYS[i], occupant])
	var title: String = "Place %s (Power %d) on which slot?" % [_node_display_name(node_id), _node_power(node_id)]
	var cap: int = _wielded_capacity()
	if cap >= 0:
		title += "\nYour weapon channels up to %d power." % cap
	_picker_overlay = SlotPickerOverlay.open(
		self, title, entries,
		func(slot: int) -> void: _send_loadout_with(node_id, slot)
	)


## Builds and sends the new loadout: places [param node_id] at [param slot]
## (replacing any occupant), or removes it everywhere when slot is -1.
func _send_loadout_with(node_id: String, slot: int) -> void:
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_category))
	var node: MasteryNode = tree.get_node_by_id(StringName(node_id)) if tree != null else null
	var root: StringName = MasteryService.chain_root_of(tree, node) if node != null else &""
	var picks: Array = _current_picks()
	for i: int in picks.size():
		var pid: String = str(picks[i])
		if pid == node_id:
			picks[i] = ""
		elif not pid.is_empty() and node != null:
			# Switching tiers: drop any OTHER tier of the same chain so the new
			# pick doesn't collide with it (one tier of a move at a time).
			var other: MasteryNode = tree.get_node_by_id(StringName(pid))
			if other != null and MasteryService.chain_root_of(tree, other) == root:
				picks[i] = ""
	if slot >= 0 and slot < picks.size():
		picks[slot] = node_id
	while not picks.is_empty() and str(picks[picks.size() - 1]).is_empty():
		picks.pop_back()
	var cap: int = _wielded_capacity()
	if cap >= 0 and slot >= 0:
		var used: int = _loadout_power_used(picks, MasteryService.tree_for(StringName(_category)))
		if used > cap:
			Toaster.toast("Not enough weapon power (%d / %d). Equip a higher-tier weapon to channel it all." % [used, cap])
	Client.request_data(
		&"mastery.loadout",
		_on_loadout_result,
		{"category": _category, "nodes": picks},
		InstanceClient.current.name
	)


func _on_loadout_result(data: Dictionary) -> void:
	match str(data.get("reason", "")):
		"in_match":
			Toaster.toast("You can't swap abilities during a match.")
		"same_chain":
			Toaster.toast("That's the same move as another slot. Only one tier of it at a time.")
	_refresh()


func _on_respec_pressed() -> void:
	Client.request_data(
		&"mastery.respec",
		func(_d: Dictionary) -> void: _refresh(),
		{"category": _category},
		InstanceClient.current.name
	)


func _close_slot_picker() -> void:
	if _picker_overlay != null and is_instance_valid(_picker_overlay):
		_picker_overlay.queue_free()
	_picker_overlay = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## The selected category's loadout, padded with "" up to the slot count so
## positional placement always has a target.
func _current_picks() -> Array:
	var picks: Array = (_state.get(_category, {}).get("loadout", []) as Array).duplicate()
	while picks.size() < SLOT_KEYS.size():
		picks.append("")
	return picks


func _node_display_name(node_id: String) -> String:
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_category))
	if tree != null:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node != null:
			return node.node_name
	return node_id


func _node_power(node_id: String) -> int:
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_category))
	if tree != null:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node != null:
			return node.tier
	return 0


func _node_icon(node: MasteryNode) -> Texture2D:
	if node.icon != null:
		return node.icon
	if node.ability != null and node.ability.icon != null:
		return node.ability.icon
	return null


func _initials(node_name: String) -> String:
	var parts: PackedStringArray = node_name.split(" ", false)
	if parts.is_empty():
		return "?"
	var out: String = parts[0].substr(0, 1)
	if parts.size() > 1:
		out += parts[1].substr(0, 1)
	return out.to_upper()


## "1.5s" / "6s". Drops the trailing ".0" so whole-second cooldowns read clean.
func _fmt_cooldown(seconds: float) -> String:
	return ("%ds" % int(seconds)) if is_equal_approx(seconds, roundf(seconds)) else ("%.1fs" % seconds)


func _passive_bonus_text(node: MasteryNode) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for modifier: StatModifier in node.passive_modifiers:
		var prefix: String = "+" if modifier.value >= 0.0 else ""
		parts.append("%s%s %s" % [prefix, _fmt_num(modifier.value), Stat.display_name(StringName(modifier.stat_name))])
	return ", ".join(parts) if not parts.is_empty() else "Always active while this weapon is wielded."


func _fmt_num(value: float) -> String:
	return ("%d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%.1f" % value)


## The wielded weapon's power capacity IF it matches the viewed category, else -1.
func _wielded_capacity() -> int:
	if str(_wielded.get("category", "")) == _category:
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


## True when the LOCAL player's wielded weapon is this category but can't channel
## the node's weight — a UI hint only; the server re-checks anyway.
func _too_heavy_for_wielded(node: MasteryNode) -> bool:
	if ClientState.local_player == null:
		return false
	var weapon_item: WeaponItem = ClientState.local_player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if weapon_item == null or String(weapon_item.category) != _category:
		return false
	return node.tier > weapon_item.capacity
