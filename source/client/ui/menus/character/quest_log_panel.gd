extends VBoxContainer
## Quest log (Character → Quests tab). Split view: quest list on the left,
## selected-quest details on the right with a pinned Track/Untrack button.
## Replaces the older list-only + modal-popup design.

## Latest quest data from the server.
var _quests: Array
var _selected_id: int

# Layout, built once in _ready.
var _list_vbox: VBoxContainer
var _detail_title: Label
var _track_button: Button
var _detail_body: VBoxContainer
var _row_buttons: Dictionary[int, Button]


func _ready() -> void:
	_build_layout()
	visibility_changed.connect(_on_visibility_changed)
	ClientState.tracked_quest_changed.connect(func(_id: int): _refresh())
	Client.subscribe(&"quest.update", func(_data: Dictionary): _refresh())
	_refresh()


func _build_layout() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 12)
	add_child(hbox)

	# Left: quest list.
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.85
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(left_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override(&"separation", 4)
	left_scroll.add_child(_list_vbox)

	# Right: details column. Header (title + track) pinned, body scrolls.
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.3
	right_col.add_theme_constant_override(&"separation", 8)
	hbox.add_child(right_col)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	right_col.add_child(header)

	_detail_title = Label.new()
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_title.add_theme_font_size_override(&"font_size", 18)
	_detail_title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	_detail_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_detail_title)

	_track_button = Button.new()
	_track_button.custom_minimum_size = Vector2(96, 36)
	_track_button.visible = false
	header.add_child(_track_button)

	var body_scroll: ScrollContainer = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(body_scroll)

	_detail_body = VBoxContainer.new()
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.add_theme_constant_override(&"separation", 8)
	body_scroll.add_child(_detail_body)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	Client.request_data(&"quest.list", _on_received, {}, InstanceClient.current.name)


func _on_received(data: Dictionary) -> void:
	_quests = data.get("quests", [])
	# Keep the current selection if it still exists; else pick a sensible
	# default (tracked quest first, then the first active one).
	if _selected_id == 0 or _find_quest(_selected_id).is_empty():
		_selected_id = _default_selection()
	_rebuild_list()
	_rebuild_detail()


func _default_selection() -> int:
	if ClientState.tracked_quest_id > 0 and not _find_quest(ClientState.tracked_quest_id).is_empty():
		return ClientState.tracked_quest_id
	for quest: Dictionary in _quests:
		if str(quest.get("state", "")) == "active":
			return int(quest.get("id", 0))
	if not _quests.is_empty():
		return int(_quests[0].get("id", 0))
	return 0


# --- List ---

func _rebuild_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()
	_row_buttons.clear()

	var active: Array = []
	var done: Array = []
	for quest: Dictionary in _quests:
		match str(quest.get("state", "")):
			"active":
				active.append(quest)
			"turned_in":
				done.append(quest)

	if active.is_empty() and done.is_empty():
		var empty: Label = Label.new()
		empty.text = "No quests yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.55
		_list_vbox.add_child(empty)
		return

	if not active.is_empty():
		_list_vbox.add_child(_make_header("Active"))
		for quest: Dictionary in active:
			_add_row(quest, true)
	if not done.is_empty():
		_list_vbox.add_child(_make_header("Completed"))
		for quest: Dictionary in done:
			_add_row(quest, false)

	# Touch/mouse drag-to-scroll for the quest list.
	DragScroll.enable(_list_vbox.get_parent() as ScrollContainer)


func _make_header(text: String) -> Label:
	var header: Label = Label.new()
	header.text = text
	header.add_theme_font_size_override(&"font_size", 13)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	return header


func _add_row(quest: Dictionary, is_active: bool) -> void:
	var quest_id: int = int(quest.get("id", 0))
	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_pressed = (quest_id == _selected_id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)
	button.text = str(quest.get("name", "?"))
	if not is_active:
		button.text += "  ✓"
		button.add_theme_color_override(&"font_color", Color(0.6, 0.75, 0.6))
	button.pressed.connect(_select_quest.bind(quest_id))
	_list_vbox.add_child(button)
	_row_buttons[quest_id] = button


func _select_quest(quest_id: int) -> void:
	_selected_id = quest_id
	for qid in _row_buttons:
		_row_buttons[qid].button_pressed = (qid == quest_id)
	_rebuild_detail()


# --- Detail ---

func _rebuild_detail() -> void:
	for child in _detail_body.get_children():
		child.queue_free()

	var quest: Dictionary = _find_quest(_selected_id)
	if quest.is_empty():
		_detail_title.text = ""
		_track_button.visible = false
		var hint: Label = Label.new()
		hint.text = "Select a quest on the left."
		hint.modulate.a = 0.55
		_detail_body.add_child(hint)
		return

	var is_active: bool = str(quest.get("state", "")) == "active"
	_detail_title.text = str(quest.get("name", "?"))

	# Track / Untrack — only for active quests.
	_track_button.visible = is_active
	if is_active:
		var quest_id: int = int(quest.get("id", 0))
		for conn in _track_button.pressed.get_connections():
			_track_button.pressed.disconnect(conn["callable"])
		if ClientState.tracked_quest_id == quest_id:
			_track_button.text = "Untrack"
			_track_button.pressed.connect(func(): ClientState.set_tracked_quest(-1))
		else:
			_track_button.text = "Track"
			_track_button.pressed.connect(func(): ClientState.set_tracked_quest(quest_id))

	var description: String = str(quest.get("description", ""))
	if not description.is_empty():
		var desc_label: Label = Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override(&"font_color", Color(0.75, 0.77, 0.83))
		_detail_body.add_child(desc_label)

	var obj_header: Label = Label.new()
	obj_header.text = "Objectives"
	obj_header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	_detail_body.add_child(obj_header)

	# ANY-mode quests (completion == 1) treat objectives as alternatives — an
	# "OR" line between them reads them as a choice, not a checklist.
	var any_mode: bool = int(quest.get("completion", 0)) == 1
	var objectives: Array = quest.get("objectives", [])
	for i in objectives.size():
		if any_mode and i > 0:
			var or_label: Label = Label.new()
			or_label.text = "OR"
			or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			or_label.add_theme_color_override(&"font_color", Color(0.65, 0.75, 0.9))
			_detail_body.add_child(or_label)
		var objective: Dictionary = objectives[i]
		var count: int = int(objective.get("count", 0))
		var required: int = int(objective.get("required", 1))
		var met: bool = count >= required
		var objective_label: Label = Label.new()
		# VISIT rows aren't counted — show a ✓ when done, not "(0/1)".
		if bool(objective.get("countable", true)):
			objective_label.text = "• %s (%d/%d)" % [str(objective.get("desc", "")), count, required]
		else:
			objective_label.text = "• %s%s" % [str(objective.get("desc", "")), "  ✓" if met else ""]
		objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if met:
			objective_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
		_detail_body.add_child(objective_label)

	_detail_body.add_child(HSeparator.new())

	var reward_label: Label = Label.new()
	reward_label.text = "Rewards: %d XP, %d gold" % [int(quest.get("reward_xp", 0)), int(quest.get("reward_gold", 0))]
	reward_label.add_theme_color_override(&"font_color", Color(0.85, 0.8, 0.4))
	_detail_body.add_child(reward_label)


func _find_quest(quest_id: int) -> Dictionary:
	for quest: Dictionary in _quests:
		if int(quest.get("id", 0)) == quest_id:
			return quest
	return {}
