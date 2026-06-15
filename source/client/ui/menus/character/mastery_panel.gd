extends VBoxContainer
## Weapon Mastery panel — split view like the Jobs panel:
##   - Left:  one row per weapon category that has a mastery tree.
##   - Right: details for the selected category. Pinned header (title + XP bar
##            + points) above a single scroll holding the three branches
##            (Offensive / Defensive / Supportive) with their nodes.
##
## Tree CONTENT (nodes, names, descriptions) comes from MasteryService.trees()
## — it's common/ data the client already has. Only per-player state (level,
## xp, points, owned nodes, loadout pick) is fetched via mastery.get.
## Spend / equip / respec are server-validated; the panel just re-fetches.

# Three weapon-agnostic playstyle pillars (LoL-runes flavored): Domination =
# aggression/damage, Resolve = durability/survival, Inspiration = utility/
# tempo/sustain. Vaguer than offensive/defensive/supportive on purpose — a
# sword can't "support allies" like a wand heal, but it CAN have tempo tricks.
const BRANCHES: Array[StringName] = [&"domination", &"resolve", &"inspiration"]
## Input labels by special-slot position (slot 1 = player_special, slot 2 =
## player_special_2). Purely cosmetic — actual binds live in the InputMap.
const SLOT_KEYS: Array[String] = ["Q", "E"]
const BRANCH_COLORS: Dictionary[StringName, Color] = {
	&"domination": Color(1.0, 0.55, 0.42),
	&"resolve": Color(0.55, 0.75, 1.0),
	&"inspiration": Color(0.65, 0.95, 0.72),
}

## Per-category server state: category (String) -> {level, xp, xp_to_next,
## points, spent: Array, loadout: String}.
var _state: Dictionary
## The wielded weapon's {category, capacity} — the "power" budget the loadout
## must fit within. Empty category = no weapon (or no mastery weapon) equipped.
var _wielded: Dictionary = {}
var _selected: String = ""

var _row_container: VBoxContainer
var _details_root: VBoxContainer
var _row_buttons: Dictionary[String, Button]
## Live slot-picker overlay (null when closed) — tracked so closing the
## character menu (or switching tabs) closes the picker with it.
var _picker_overlay: Control


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_build_layout()
	_refresh()


func _build_layout() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 12)
	add_child(hbox)

	# Left: category list.
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.6
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(left_scroll)

	_row_container = VBoxContainer.new()
	_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_container.add_theme_constant_override(&"separation", 4)
	left_scroll.add_child(_row_container)

	# Right: details — header stays pinned, branches scroll (one scroll per
	# region, same lesson as the Jobs panel).
	_details_root = VBoxContainer.new()
	_details_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_root.size_flags_stretch_ratio = 1.6
	_details_root.add_theme_constant_override(&"separation", 8)
	hbox.add_child(_details_root)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()
	else:
		_close_slot_picker()


func _close_slot_picker() -> void:
	if _picker_overlay != null and is_instance_valid(_picker_overlay):
		_picker_overlay.queue_free()
	_picker_overlay = null


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	Client.request_data(&"mastery.get", _on_mastery_received, {}, InstanceClient.current.name)


func _on_mastery_received(data: Dictionary) -> void:
	_state = data.get("masteries", {})
	_wielded = data.get("wielded", {})
	_rebuild_rows()
	if _selected == "" or MasteryService.tree_for(StringName(_selected)) == null:
		_selected = ""
		for category: StringName in MasteryService.trees():
			_selected = String(category)
			break
	_rebuild_details()


# ---------------------------------------------------------------------------
# Left column — categories
# ---------------------------------------------------------------------------

func _rebuild_rows() -> void:
	for child in _row_container.get_children():
		child.queue_free()
	_row_buttons.clear()

	if MasteryService.trees().is_empty():
		var hint: Label = Label.new()
		hint.text = "No mastery trees exist yet."
		hint.modulate.a = 0.55
		_row_container.add_child(hint)
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
		button.custom_minimum_size = Vector2(0, 40)
		var badge: String = "   ●%d" % points if points > 0 else ""
		button.text = "%s — Lv %d%s" % [display, level, badge] if level > 0 else "%s — unpracticed" % display
		if points > 0:
			button.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5))
		button.pressed.connect(_select_category.bind(String(category)))
		_row_container.add_child(button)
		_row_buttons[String(category)] = button


func _select_category(category: String) -> void:
	_selected = category
	for key: String in _row_buttons:
		_row_buttons[key].button_pressed = (key == _selected)
	_rebuild_details()


# ---------------------------------------------------------------------------
# Right column — selected category's tree
# ---------------------------------------------------------------------------

func _rebuild_details() -> void:
	for child in _details_root.get_children():
		child.queue_free()

	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_selected))
	if tree == null:
		var empty: Label = Label.new()
		empty.text = "Select a weapon category on the left."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.55
		_details_root.add_child(empty)
		return

	var info: Dictionary = _state.get(_selected, {})
	var level: int = int(info.get("level", 0))
	var points: int = int(info.get("points", 0))
	var display: String = tree.display_name if not tree.display_name.is_empty() else _selected.capitalize()

	# --- Pinned header ---
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	_details_root.add_child(header)

	var title: Label = Label.new()
	title.text = "%s Mastery — Lv %d" % [display, level] if level > 0 else "%s Mastery" % display
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	if level > 0 and not (info.get("spent", []) as Array).is_empty():
		var respec: Button = Button.new()
		respec.text = "Reset points"
		respec.custom_minimum_size = Vector2(0, 34)
		respec.pressed.connect(_on_respec_pressed)
		header.add_child(respec)

	if level <= 0:
		var hint: Label = Label.new()
		hint.text = "Defeat an enemy wielding a %s to begin its mastery." % display.to_lower()
		hint.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details_root.add_child(hint)
	else:
		var bar: ProgressBar = ProgressBar.new()
		bar.theme_type_variation = &"XPBar"
		bar.min_value = 0
		bar.max_value = maxi(1, int(info.get("xp_to_next", 1)))
		bar.value = int(info.get("xp", 0))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 16)
		_details_root.add_child(bar)

		var status: Label = Label.new()
		var at_cap: bool = level >= int(PlayerResource.MASTERY_LEVEL_CAP)
		var xp_text: String = "Max level" if at_cap else "%d / %d XP" % [int(info.get("xp", 0)), int(info.get("xp_to_next", 1))]
		status.text = "%s    —    %d point%s available" % [xp_text, points, "" if points == 1 else "s"]
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5) if points > 0 else Color(0.7, 0.72, 0.78))
		status.add_theme_font_size_override(&"font_size", 12)
		_details_root.add_child(status)

	# --- Power line, two modes ---
	#  1. wielding a weapon of THIS category → "used / capacity" (red if over).
	#  2. otherwise → just the loadout's total power, so the player still sees
	#     what this loadout would demand of a weapon.
	var cap: int = _wielded_capacity()
	var used: int = _loadout_power_used(info.get("loadout", []), tree)
	if cap >= 0 or used > 0:
		var power: Label = Label.new()
		power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		power.add_theme_font_size_override(&"font_size", 12)
		power.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if cap < 0:
			power.text = "Loadout power: %d  (equip a %s to channel it)" % [used, display.to_lower()]
			power.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.78))
		elif used > cap:
			power.text = "Weapon power: %d / %d — over capacity, the heaviest ability won't channel" % [used, cap]
			power.add_theme_color_override(&"font_color", Color(1.0, 0.55, 0.4))
		else:
			power.text = "Weapon power: %d / %d used" % [used, cap]
			power.add_theme_color_override(&"font_color", Color(0.7, 0.85, 1.0))
		_details_root.add_child(power)

	# --- Branches (single scroll) ---
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_root.add_child(scroll)

	var branches: VBoxContainer = VBoxContainer.new()
	branches.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branches.add_theme_constant_override(&"separation", 6)
	scroll.add_child(branches)

	for branch: StringName in BRANCHES:
		var nodes: Array[MasteryNode] = []
		for node: MasteryNode in tree.nodes:
			if node.branch == branch:
				nodes.append(node)
		if nodes.is_empty():
			continue
		nodes.sort_custom(func(a: MasteryNode, b: MasteryNode) -> bool: return a.tier < b.tier)

		var branch_label: Label = Label.new()
		branch_label.text = String(branch).capitalize()
		branch_label.add_theme_font_size_override(&"font_size", 13)
		branch_label.add_theme_color_override(&"font_color", BRANCH_COLORS.get(branch, Color.WHITE))
		branches.add_child(branch_label)

		for node: MasteryNode in nodes:
			branches.add_child(_make_node_row(node, info))


# ---------------------------------------------------------------------------
# One node row: tier pip + name, description, and a state-dependent button.
# ---------------------------------------------------------------------------

func _make_node_row(node: MasteryNode, info: Dictionary) -> Control:
	var owned: bool = (info.get("spent", []) as Array).has(String(node.id))
	var loadout: Array = info.get("loadout", [])
	var slot_index: int = loadout.find(String(node.id))
	var equipped: bool = slot_index >= 0
	var level: int = int(info.get("level", 0))
	var points: int = int(info.get("points", 0))
	var required_level: int = int(MasteryService.TIER_UNLOCK_LEVEL.get(node.tier, 1))

	# Upgrade-chain state: a superseded tier (a higher one in its chain is owned)
	# isn't separately equippable, and a chain node can only be LEARNED once its
	# lower tier is owned.
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_selected))
	var owned_set: Dictionary = {}
	for owned_id in info.get("spent", []):
		owned_set[String(owned_id)] = true
	var superseded: bool = node.ability != null and tree != null and MasteryService.is_superseded(tree, owned_set, node)
	var prereq_id: String = String(node.upgrades)
	var prereq_owned: bool = prereq_id.is_empty() or owned_set.has(prereq_id)
	var prereq_name: String = _node_display_name(prereq_id) if not prereq_id.is_empty() else ""

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

	# Abilities show their POWER cost (= weight the weapon must channel);
	# passives are always-on, so no power.
	var name_label: Label = Label.new()
	if node.ability != null:
		name_label.text = "%s  —  Power %d" % [node.node_name, node.tier]
	else:
		name_label.text = "%s  —  Passive" % node.node_name
	name_vbox.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.text = node.description
	desc_label.add_theme_color_override(&"font_color", Color(0.62, 0.74, 0.86))
	desc_label.add_theme_font_size_override(&"font_size", 11)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_vbox.add_child(desc_label)

	if owned and node.ability != null and superseded:
		# A lower tier you've already upgraded past — kept for the record but
		# no longer the move you wield.
		var up_label: Label = Label.new()
		up_label.text = "Upgraded"
		up_label.add_theme_font_size_override(&"font_size", 11)
		up_label.add_theme_color_override(&"font_color", Color(0.6, 0.62, 0.7))
		up_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(up_label)
	elif owned and node.ability != null:
		# Inline (not tooltip-only — hover is easy to miss) capacity warning.
		if _too_heavy_for_wielded(node):
			var heavy_label: Label = Label.new()
			heavy_label.text = "Too heavy for your current weapon — stays stored until one can channel weight %d." % node.tier
			heavy_label.add_theme_color_override(&"font_color", Color(1.0, 0.75, 0.45))
			heavy_label.add_theme_font_size_override(&"font_size", 11)
			heavy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_vbox.add_child(heavy_label)

		var equip_button: Button = Button.new()
		equip_button.custom_minimum_size = Vector2(96, 38)
		equip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		equip_button.toggle_mode = true
		equip_button.button_pressed = equipped
		if equipped:
			var key: String = SLOT_KEYS[slot_index] if slot_index < SLOT_KEYS.size() else str(slot_index + 1)
			equip_button.text = "Slot %d (%s)" % [slot_index + 1, key]
		else:
			equip_button.text = "Equip"
		# Equipping opens the slot picker; pressing an equipped node unequips it.
		equip_button.pressed.connect(_on_equip_pressed.bind(String(node.id), equipped))
		hbox.add_child(equip_button)
	elif owned:
		var active_label: Label = Label.new()
		active_label.text = "Active with\nthis weapon"
		active_label.add_theme_font_size_override(&"font_size", 10)
		active_label.add_theme_color_override(&"font_color", Color(0.6, 0.95, 0.65))
		active_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		active_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(active_label)
	else:
		var learn_button: Button = Button.new()
		learn_button.custom_minimum_size = Vector2(110, 38)
		learn_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not prereq_owned:
			# Chain progression — must learn the lower tier first.
			learn_button.text = "Needs %s" % prereq_name
			learn_button.disabled = true
		elif level < required_level:
			learn_button.text = "Lv %d" % required_level
			learn_button.disabled = true
		else:
			learn_button.text = "Learn (%d)" % node.tier
			learn_button.disabled = points < node.tier
		learn_button.pressed.connect(_on_learn_pressed.bind(String(node.id)))
		hbox.add_child(learn_button)

	return panel


## True when the LOCAL player's wielded weapon is this category but can't
## channel the node's weight — purely a UI hint, the server re-checks anyway.
func _too_heavy_for_wielded(node: MasteryNode) -> bool:
	if ClientState.local_player == null:
		return false
	var weapon_item: WeaponItem = ClientState.local_player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if weapon_item == null or String(weapon_item.category) != _selected:
		return false
	return node.tier > weapon_item.capacity


func _on_learn_pressed(node_id: String) -> void:
	Client.request_data(
		&"mastery.spend",
		func(_d: Dictionary) -> void: _refresh(),
		{"category": _selected, "node": node_id},
		InstanceClient.current.name
	)


func _on_equip_pressed(node_id: String, was_equipped: bool) -> void:
	if was_equipped:
		_send_loadout_with(node_id, -1) # -1 = remove from wherever it sits
		return
	_open_slot_picker(node_id)


## Asks WHICH input slot the ability goes on, via the shared SlotPickerOverlay
## (same component as the inventory hotkey assigner — one picker UX
## everywhere). Hosted on the character menu's scene root so it covers the
## whole menu and dies with it.
func _open_slot_picker(node_id: String) -> void:
	_close_slot_picker()
	var picks: Array = _current_picks()
	var entries: PackedStringArray = PackedStringArray()
	for i: int in SLOT_KEYS.size():
		var occ_id: String = str(picks[i])
		var occupant: String = "empty"
		if not occ_id.is_empty():
			occupant = "%s (Power %d)" % [_node_display_name(occ_id), _node_power(occ_id)]
		entries.append("Slot %d (%s)  —  %s" % [i + 1, SLOT_KEYS[i], occupant])
	var title: String = "Place %s (Power %d) on which slot?" % [_node_display_name(node_id), _node_power(node_id)]
	var cap: int = _wielded_capacity()
	if cap >= 0:
		title += "\nYour weapon channels up to %d power." % cap
	var host: Control = (owner as Control) if owner is Control else self
	_picker_overlay = SlotPickerOverlay.open(
		host, title, entries,
		func(slot: int) -> void: _send_loadout_with(node_id, slot)
	)


## Builds and sends the new loadout: places [param node_id] at [param slot]
## (replacing any occupant), or removes it everywhere when slot is -1. Moving
## an already-equipped ability clears its old slot, leaving a deliberate hole
## ("" entry) so other picks keep their key.
func _send_loadout_with(node_id: String, slot: int) -> void:
	var picks: Array = _current_picks()
	for i: int in picks.size():
		if str(picks[i]) == node_id:
			picks[i] = ""
	if slot >= 0 and slot < picks.size():
		picks[slot] = node_id
	while not picks.is_empty() and str(picks[picks.size() - 1]).is_empty():
		picks.pop_back()
	# Warn (but still store) if the new loadout overruns the wielded weapon's
	# power — the heaviest pick mounts inert until a weapon that can channel it.
	var cap: int = _wielded_capacity()
	if cap >= 0 and slot >= 0:
		var used: int = _loadout_power_used(picks, MasteryService.tree_for(StringName(_selected)))
		if used > cap:
			Toaster.toast("Not enough weapon power (%d / %d). Equip a higher-tier weapon to channel it all." % [used, cap])
	Client.request_data(
		&"mastery.loadout",
		_on_loadout_result,
		{"category": _selected, "nodes": picks},
		InstanceClient.current.name
	)


## The selected category's loadout, padded with "" up to the slot count so
## positional placement always has a target.
func _current_picks() -> Array:
	var info: Dictionary = _state.get(_selected, {})
	var picks: Array = (info.get("loadout", []) as Array).duplicate()
	while picks.size() < SLOT_KEYS.size():
		picks.append("")
	return picks


func _node_display_name(node_id: String) -> String:
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_selected))
	if tree != null:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node != null:
			return node.node_name
	return node_id


## An ability node's power cost (= tier = the weight a weapon must channel).
func _node_power(node_id: String) -> int:
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(_selected))
	if tree != null:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node != null:
			return node.tier
	return 0


## The wielded weapon's power capacity IF it matches the viewed category, else
## -1 (no weapon of this category in hand — capacity is meaningless to show).
func _wielded_capacity() -> int:
	if str(_wielded.get("category", "")) == _selected:
		return int(_wielded.get("capacity", 0))
	return -1


## Total power the loadout picks consume (sum of their tiers; "" holes skipped).
func _loadout_power_used(picks: Array, tree: MasteryTreeResource) -> int:
	if tree == null:
		return 0
	var total: int = 0
	for pick in picks:
		var id: String = str(pick)
		if id.is_empty():
			continue
		var node: MasteryNode = tree.get_node_by_id(StringName(id))
		if node != null:
			total += node.tier
	return total


func _on_loadout_result(data: Dictionary) -> void:
	match str(data.get("reason", "")):
		"in_match":
			Toaster.toast("You can't swap abilities during a match.")
		"same_chain":
			Toaster.toast("That's the same move as another slot — only one tier of it at a time.")
	_refresh()


func _on_respec_pressed() -> void:
	Client.request_data(
		&"mastery.respec",
		func(_d: Dictionary) -> void: _refresh(),
		{"category": _selected},
		InstanceClient.current.name
	)
