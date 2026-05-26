extends PanelContainer
## HUD quest tracker: shows a single quest (the one pinned via the log, else the first
## active quest) with its objectives + live progress. Hidden when there's nothing to track.
## Click-through so it never blocks world interaction.

var _content: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", 2)
	margin.add_child(_content)

	hide()
	ClientState.tracked_quest_changed.connect(func(_id: int): _refresh())
	Client.subscribe(&"quest.update", func(_data: Dictionary): _refresh())
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _refresh())
	_refresh()


func _refresh() -> void:
	if InstanceClient.current == null:
		hide()
		return
	Client.request_data(&"quest.list", _on_received, {}, InstanceClient.current.name)


func _on_received(data: Dictionary) -> void:
	# -1 = explicitly untracked (player cleared the HUD); stay hidden.
	if ClientState.tracked_quest_id == -1:
		hide()
		return

	var tracked: Dictionary = {}
	var first_active: Dictionary = {}
	for quest: Dictionary in data.get("quests", []):
		if str(quest.get("state", "")) != "active":
			continue
		if first_active.is_empty():
			first_active = quest
		if int(quest.get("id", 0)) == ClientState.tracked_quest_id:
			tracked = quest

	if tracked.is_empty():
		if first_active.is_empty():
			hide()
			return
		# Auto-track the first active quest (set directly, no signal, to avoid a refetch loop).
		tracked = first_active
		ClientState.tracked_quest_id = int(first_active.get("id", 0))

	_display(tracked)
	show()


func _display(quest: Dictionary) -> void:
	for child in _content.get_children():
		child.queue_free()

	var name_label: Label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = str(quest.get("name", "?"))
	name_label.add_theme_color_override(&"font_color", Color(0.85, 0.8, 0.4))
	_content.add_child(name_label)

	for objective: Dictionary in quest.get("objectives", []):
		var count: int = int(objective.get("count", 0))
		var required: int = int(objective.get("required", 1))
		var objective_label: Label = Label.new()
		objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		objective_label.text = "• %s (%d/%d)" % [str(objective.get("desc", "")), count, required]
		if count >= required:
			objective_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
		_content.add_child(objective_label)
