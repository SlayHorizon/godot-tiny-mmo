extends VBoxContainer
## Global quest log (Character menu "Quests" tab). Lists active quests with live progress,
## a Track button (pins one to the HUD tracker) and a Details button (full info popup),
## plus completed quests greyed out.

@onready var quest_list: VBoxContainer = %QuestLogList

## Latest quest data from the server (used to (re)build the details popup).
var _quests: Array
## Full-rect modal showing a single quest's details (description + objectives + rewards).
var _overlay: Control
var _detail_root: VBoxContainer
## Quest currently shown in the details popup (0 = closed).
var _open_quest_id: int


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	ClientState.tracked_quest_changed.connect(func(_id: int): _refresh())
	Client.subscribe(&"quest.update", func(_data: Dictionary): _refresh())


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()
	elif _overlay:
		_close_detail()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	Client.request_data(&"quest.list", _on_received, {}, InstanceClient.current.name)


func _on_received(data: Dictionary) -> void:
	_quests = data.get("quests", [])
	_rebuild_list()
	if _open_quest_id != 0 and _overlay and _overlay.visible:
		_rebuild_detail()


# --- List ---

func _rebuild_list() -> void:
	for child in quest_list.get_children():
		child.queue_free()

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
		quest_list.add_child(empty)
		return

	for quest: Dictionary in active:
		quest_list.add_child(_make_entry(quest, true))
	for quest: Dictionary in done:
		quest_list.add_child(_make_entry(quest, false))


func _make_entry(quest: Dictionary, is_active: bool) -> PanelContainer:
	var quest_id: int = int(quest.get("id", 0))

	var panel: PanelContainer = PanelContainer.new()
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 2)
	margin.add_child(vbox)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	vbox.add_child(header)

	var name_label: Label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = str(quest.get("name", "?"))
	header.add_child(name_label)

	if is_active:
		# The tracked quest gets an Untrack button (clears the HUD); others a Track button.
		var track_button: Button = Button.new()
		track_button.custom_minimum_size = Vector2(0, 40)
		if ClientState.tracked_quest_id == quest_id:
			track_button.text = "Untrack"
			track_button.pressed.connect(func(): ClientState.set_tracked_quest(-1))
		else:
			track_button.text = "Track"
			track_button.pressed.connect(func(): ClientState.set_tracked_quest(quest_id))
		header.add_child(track_button)
	else:
		name_label.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.65))
		var done_label: Label = Label.new()
		done_label.text = "Completed ✓"
		done_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
		header.add_child(done_label)

	var details_button: Button = Button.new()
	details_button.text = "Details"
	details_button.custom_minimum_size = Vector2(0, 40)
	details_button.pressed.connect(_open_detail.bind(quest_id))
	header.add_child(details_button)

	if is_active:
		for objective: Dictionary in quest.get("objectives", []):
			var count: int = int(objective.get("count", 0))
			var required: int = int(objective.get("required", 1))
			var objective_label: Label = Label.new()
			objective_label.text = "• %s (%d/%d)" % [str(objective.get("desc", "")), count, required]
			if count >= required:
				objective_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
			vbox.add_child(objective_label)

	return panel


# --- Details popup ---

func _open_detail(quest_id: int) -> void:
	_open_quest_id = quest_id
	if _overlay == null:
		_build_overlay()
	_rebuild_detail()
	_overlay.show()


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_detail())
	_overlay.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	var card_margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		card_margin.add_theme_constant_override("margin_" + side, 14)
	for side: String in ["top", "bottom"]:
		card_margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(card_margin)

	_detail_root = VBoxContainer.new()
	_detail_root.add_theme_constant_override(&"separation", 6)
	card_margin.add_child(_detail_root)

	var host: Node = owner if owner else self
	host.add_child(_overlay)


func _close_detail() -> void:
	_open_quest_id = 0
	if _overlay:
		_overlay.hide()


func _rebuild_detail() -> void:
	if _detail_root == null:
		return
	var quest: Dictionary = _find_quest(_open_quest_id)
	if quest.is_empty():
		_close_detail()
		return

	for child in _detail_root.get_children():
		child.queue_free()

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	_detail_root.add_child(header)

	var title: Label = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = str(quest.get("name", "?"))
	header.add_child(title)

	var close_button: Button = Button.new()
	close_button.text = "✕"
	close_button.pressed.connect(_close_detail)
	header.add_child(close_button)

	var description: String = str(quest.get("description", ""))
	if not description.is_empty():
		var desc_label: Label = Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.75))
		_detail_root.add_child(desc_label)

	for objective: Dictionary in quest.get("objectives", []):
		var count: int = int(objective.get("count", 0))
		var required: int = int(objective.get("required", 1))
		var objective_label: Label = Label.new()
		objective_label.text = "• %s (%d/%d)" % [str(objective.get("desc", "")), count, required]
		if count >= required:
			objective_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
		_detail_root.add_child(objective_label)

	var reward_label: Label = Label.new()
	reward_label.text = "Rewards: %d XP, %d gold" % [int(quest.get("reward_xp", 0)), int(quest.get("reward_gold", 0))]
	reward_label.add_theme_color_override(&"font_color", Color(0.85, 0.8, 0.4))
	_detail_root.add_child(reward_label)


func _find_quest(quest_id: int) -> Dictionary:
	for quest: Dictionary in _quests:
		if int(quest.get("id", 0)) == quest_id:
			return quest
	return {}
