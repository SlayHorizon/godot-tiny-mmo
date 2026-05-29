extends Control
## Quest-giver dialog. Opened by name "quest" with a giver id. Lists the quests that
## giver offers with the player's state on each: Accept (new), progress (active), Turn in
## (active + complete), or Completed (turned in). Quest data is server-authoritative.

var _giver_id: int

@onready var title_label: Label = %TitleLabel
@onready var quest_list: VBoxContainer = %QuestList


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible and _giver_id > 0:
		_refresh()


func open(giver_id: int) -> void:
	_giver_id = giver_id
	_refresh()


func _refresh() -> void:
	var result: Array = await Client.request_data_await(&"quest.list", {"giver": _giver_id}, InstanceClient.current.name)
	if result[1] != OK:
		return
	var data: Dictionary = result[0]
	var giver_name: String = str(data.get("giver_name", ""))
	title_label.text = giver_name if not giver_name.is_empty() else "Quests"
	_build(data.get("quests", []))


func _build(quests: Array) -> void:
	for child in quest_list.get_children():
		child.queue_free()

	if quests.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nothing available right now."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quest_list.add_child(empty)
		return

	for quest: Dictionary in quests:
		quest_list.add_child(_make_quest_entry(quest))


func _make_quest_entry(quest: Dictionary) -> PanelContainer:
	var state: String = str(quest.get("state", ""))
	var complete: bool = bool(quest.get("complete", false))

	var panel: PanelContainer = PanelContainer.new()
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 3)
	margin.add_child(vbox)

	var name_label: Label = Label.new()
	name_label.text = str(quest.get("name", "?"))
	vbox.add_child(name_label)

	var description: String = str(quest.get("description", ""))
	if not description.is_empty():
		var desc_label: Label = Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.75))
		vbox.add_child(desc_label)

	for objective: Dictionary in quest.get("objectives", []):
		var count: int = int(objective.get("count", 0))
		var required: int = int(objective.get("required", 1))
		var objective_label: Label = Label.new()
		objective_label.text = "• %s (%d/%d)" % [str(objective.get("desc", "")), count, required]
		if count >= required:
			objective_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
		vbox.add_child(objective_label)

	var reward_label: Label = Label.new()
	reward_label.text = "Rewards: %d XP, %d gold" % [int(quest.get("reward_xp", 0)), int(quest.get("reward_gold", 0))]
	reward_label.add_theme_color_override(&"font_color", Color(0.85, 0.8, 0.4))
	vbox.add_child(reward_label)

	vbox.add_child(_make_action(
		int(quest.get("id", 0)),
		state,
		complete,
		bool(quest.get("meets_level", true)),
		int(quest.get("min_level", 0)),
	))
	return panel


func _make_action(quest_id: int, state: String, complete: bool, meets_level: bool, min_level: int) -> Control:
	match state:
		"":
			# Level gate — show requirement instead of an Accept button the
			# server would just reject anyway.
			if not meets_level:
				var locked: Label = Label.new()
				locked.text = "Requires level %d" % min_level
				locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				locked.add_theme_color_override(&"font_color", Color(0.7, 0.5, 0.5))
				return locked
			var accept: Button = Button.new()
			accept.text = "Accept"
			accept.custom_minimum_size = Vector2(0, 40)
			accept.pressed.connect(_on_accept.bind(quest_id))
			return accept
		"active":
			if complete:
				var turn_in: Button = Button.new()
				turn_in.text = "Turn in"
				turn_in.custom_minimum_size = Vector2(0, 40)
				turn_in.pressed.connect(_on_turn_in.bind(quest_id))
				return turn_in
			var in_progress: Label = Label.new()
			in_progress.text = "In progress…"
			in_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			return in_progress
		_:
			var done: Label = Label.new()
			done.text = "Completed ✓"
			done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			done.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
			return done


func _on_accept(quest_id: int) -> void:
	var result: Array = await Client.request_data_await(&"quest.accept", {"giver": _giver_id, "id": quest_id}, InstanceClient.current.name)
	if result[1] == OK and result[0].get("ok", false):
		ClientState.set_tracked_quest(quest_id) # latest accepted becomes the tracked one
	_refresh()


func _on_turn_in(quest_id: int) -> void:
	await Client.request_data_await(&"quest.turn_in", {"giver": _giver_id, "id": quest_id}, InstanceClient.current.name)
	_refresh()


func _on_close_button_pressed() -> void:
	hide()
