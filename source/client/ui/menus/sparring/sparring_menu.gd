extends Control
## Spar lobby — opened by clicking a DuelMaster station. Renders ONE COLUMN PER
## TEAM (however many the station defines: 1v1, 2v2, 1v3, 1v1v1, ...), each with
## its roster of names, empty slots, and a Join button. Updates live as players
## join/leave; auto-hides when the match starts (the countdown lives on the HUD).
##
## Opened via HUD.display_menu("sparring", master_id) → open(arg).

var _master_id: int = 0
var _master_name: String = "Arena"
var _your_team: int = -1

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Live roster pushes (anyone joining/leaving this station) + auto-hide on start.
	Client.subscribe(&"sparring.queue.update", _on_queue_update)
	Client.subscribe(&"sparring.match.state", _on_match_state)


func open(master_id: int) -> void:
	_master_id = master_id
	_your_team = -1
	_build_shell()
	_set_message("Loading…")
	_refresh()


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.7)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 18)
	pad.add_theme_constant_override(&"margin_right", 18)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 12)
	pad.add_child(_content)


func _refresh() -> void:
	Client.request_data(
		&"sparring.info", _apply_state, {"master_id": _master_id},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _apply_state(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		var reason: String = str(response.get("reason", ""))
		Toaster.toast({
			"too_far": "You're too far from the arena.",
			"in_match": "You're already in a match.",
			"already_in_match": "You're already in a match.",
			"no_master": "Arena not found.",
			"bad_station": "This arena isn't set up yet.",
			"team_full": "That team is full.",
		}.get(reason, "Sparring unavailable."))
		hide()
		return
	if bool(response.get("started", false)):
		hide()
		return
	_render(response)


func _render(data: Dictionary) -> void:
	if _content == null:
		_build_shell()
	for c: Node in _content.get_children():
		c.queue_free()
	if data.has("your_team"):
		_your_team = int(data["your_team"])
	_master_name = str(data.get("master_name", _master_name))
	var rosters: Array = data.get("teams", [])
	var capacities: Array = data.get("capacities", [])
	var team_names: Array = data.get("team_names", [])

	# "1v1" / "2v2" / "1v3" / "1v1v1" label straight from the capacities.
	var shape: PackedStringArray = PackedStringArray()
	for c: Variant in capacities:
		shape.append(str(int(c)))
	var title: Label = Label.new()
	title.text = "%s — %s" % [_master_name, "v".join(shape)]
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	_content.add_child(title)

	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 16)
	_content.add_child(cols)
	for t: int in rosters.size():
		var label: String = str(team_names[t]) if t < team_names.size() else "Team %d" % (t + 1)
		cols.add_child(_team_column(t, label, rosters[t], int(capacities[t]) if t < capacities.size() else 1))

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(buttons)
	if _your_team >= 0:
		var leave: Button = Button.new()
		leave.text = "Leave queue"
		leave.custom_minimum_size = Vector2(0, 40)
		leave.pressed.connect(_on_leave)
		buttons.add_child(leave)
	var close: Button = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(hide)
	buttons.add_child(close)


func _team_column(team_index: int, header: String, names: Array, capacity: int) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(170, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 6)

	var head: Label = Label.new()
	head.text = "%s  (%d/%d)" % [header, names.size(), capacity]
	head.add_theme_color_override(&"font_color", Color(0.8, 0.85, 1.0))
	col.add_child(head)

	for n: Variant in names:
		var row: Label = Label.new()
		row.text = "• " + str(n)
		col.add_child(row)
	for _i: int in range(names.size(), capacity): # empty slots
		var empty: Label = Label.new()
		empty.text = "• —"
		empty.modulate.a = 0.4
		col.add_child(empty)

	var join: Button = Button.new()
	join.text = "Join"
	join.custom_minimum_size = Vector2(0, 40)
	# Can't join if already queued anywhere, or this side is full.
	join.disabled = _your_team >= 0 or names.size() >= capacity
	join.pressed.connect(_on_join.bind(team_index))
	col.add_child(join)
	return col


func _on_join(team_index: int) -> void:
	Client.request_data(
		&"sparring.queue", _apply_state,
		{"master_id": _master_id, "action": "join", "team": team_index},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _on_leave() -> void:
	_your_team = -1
	Client.request_data(
		&"sparring.queue", _apply_state,
		{"master_id": _master_id, "action": "leave"},
		InstanceClient.current.name if InstanceClient.current else ""
	)


## Live roster push. The broadcast carries rosters/capacities/team_names but not
## per-viewer fields — keep our locally-known team + station name.
func _on_queue_update(payload: Dictionary) -> void:
	if not visible or int(payload.get("master_id", 0)) != _master_id:
		return
	payload["master_name"] = _master_name
	_render(payload)


func _on_match_state(payload: Dictionary) -> void:
	if bool(payload.get("in_match", false)) and visible:
		hide()


func _set_message(text: String) -> void:
	if _content == null:
		_build_shell()
	for c: Node in _content.get_children():
		c.queue_free()
	var label: Label = Label.new()
	label.text = text
	_content.add_child(label)
