extends Control
## Dungeon lobby — opened by clicking a DungeonMaster station. One shared queue
## (no teams): see who's in, Join / Leave, then Start to send the whole party into
## a PRIVATE dungeon, or Solo to go in alone. Auto-hides when the run starts.
##
## Opened via HUD.display_menu("dungeon", master_id) → open(arg).

var _master_id: int = 0
var _master_name: String = "Dungeon"
var _queued: bool = false
## Hard mode for this launch (the starter's pick decides the run).
var _hard: bool = false

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Client.subscribe(&"dungeon.lobby.update", _on_lobby_update)


func open(master_id: int) -> void:
	_master_id = master_id
	_queued = false
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
	card.custom_minimum_size = Vector2(360, 0)
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
		&"dungeon.info", _apply_state, {"master_id": _master_id},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _apply_state(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		var reason: String = str(response.get("reason", ""))
		Toaster.toast({
			"too_far": "You're too far from the dungeon.",
			"no_master": "Dungeon not found.",
			"in_run": "You're already in a dungeon.",
			"full": "The party is full.",
		}.get(reason, "Dungeon unavailable."))
		hide()
		return
	if bool(response.get("started", false)):
		hide() # we're being sent into the run
		return
	_render(response)


func _render(data: Dictionary) -> void:
	if _content == null:
		_build_shell()
	for c: Node in _content.get_children():
		c.queue_free()
	if data.has("queued"):
		_queued = bool(data["queued"])
	_master_name = str(data.get("master_name", _master_name))
	var members: Array = data.get("members", [])
	var capacity: int = int(data.get("capacity", 4))

	var title: Label = Label.new()
	title.text = "%s  (%d/%d)" % [_master_name, members.size(), capacity]
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	_content.add_child(title)

	for n: Variant in members:
		var row: Label = Label.new()
		row.text = "• " + str(n)
		_content.add_child(row)
	for _i: int in range(members.size(), capacity): # empty slots
		var empty: Label = Label.new()
		empty.text = "• —"
		empty.modulate.a = 0.4
		_content.add_child(empty)

	var hard_toggle: CheckButton = CheckButton.new()
	hard_toggle.text = "Hard Mode"
	hard_toggle.button_pressed = _hard
	hard_toggle.tooltip_text = "Tougher mobs and boss, richer reward. Separate daily lockout."
	hard_toggle.toggled.connect(func(on: bool) -> void: _hard = on)
	_content.add_child(hard_toggle)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(buttons)
	if _queued:
		buttons.add_child(_button("Start", _on_start))
		buttons.add_child(_button("Leave", _on_leave))
	else:
		buttons.add_child(_button("Join", _on_join))
		buttons.add_child(_button("Solo", _on_solo))
	buttons.add_child(_button("Close", hide))


func _button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(callback)
	return b


func _send(action: String) -> void:
	Client.request_data(
		&"dungeon.queue", _apply_state,
		{"master_id": _master_id, "action": action, "hard": _hard},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _on_join() -> void:
	_send("join")


func _on_leave() -> void:
	_queued = false
	_send("leave")


func _on_start() -> void:
	_send("start")


func _on_solo() -> void:
	_send("solo")


## Live roster push (someone joined/left). The push doesn't carry our own queued
## state, so keep what we know locally.
func _on_lobby_update(payload: Dictionary) -> void:
	if not visible or int(payload.get("master_id", 0)) != _master_id:
		return
	payload["master_name"] = _master_name
	payload["queued"] = _queued
	_render(payload)


func _set_message(text: String) -> void:
	if _content == null:
		_build_shell()
	for c: Node in _content.get_children():
		c.queue_free()
	var label: Label = Label.new()
	label.text = text
	_content.add_child(label)
