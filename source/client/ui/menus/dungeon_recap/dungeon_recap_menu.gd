extends Control
## Shown when a dungeon run ENDS — CLEARED (name, time, reward) or FAILED (a hardcore
## wipe: name, time survived, no reward). The payload's "failed" flag picks the variant.
## Opened via open_menu_requested(&"dungeon_recap", recap_dict). Auto-closes when the
## server ejects the party (after eject_in seconds), or on Close.

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(data: Dictionary) -> void:
	var failed: bool = bool(data.get("failed", false))
	_build_shell(failed)

	if failed:
		_title("Run Failed", Color(1.0, 0.45, 0.4))
		_line(str(data.get("dungeon", "Dungeon")), Color(0.86, 0.8, 0.82), 16)
		_line("Survived: %ds" % int(data.get("seconds", 0)))
		_line("The party has fallen — no reward.", Color(0.92, 0.58, 0.52))
	else:
		_title("Dungeon Cleared!")
		_line(str(data.get("dungeon", "Dungeon")), Color(0.8, 0.85, 1.0), 16)
		_line("Completion time: %ds" % int(data.get("seconds", 0)))
		_render_reward(data.get("reward", {}) as Dictionary)

	var eject: int = int(data.get("eject_in", 15))
	_line("Returning to town in ~%ds…" % eject, Color(0.7, 0.74, 0.82))

	var close: Button = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(hide)
	_content.add_child(close)

	# Auto-close when the party is sent home.
	if eject > 0:
		get_tree().create_timer(float(eject)).timeout.connect(hide, CONNECT_ONE_SHOT)


## Render the reward block from the server payload: a gold + item list on a
## payout, or a "come back later" note when the soft daily lockout suppressed it.
func _render_reward(reward: Dictionary) -> void:
	if reward.is_empty():
		return
	if bool(reward.get("locked", false)):
		var hours: int = int(ceil(float(reward.get("available_in", 0)) / 3600.0))
		_line("Already cleared today — reward in ~%dh" % maxi(hours, 1), Color(0.86, 0.7, 0.5))
		return
	_line("Rewards", Color(1.0, 0.92, 0.55), 15)
	var gold: int = int(reward.get("gold", 0))
	if gold > 0:
		_line("%d gold" % gold, Color(1.0, 0.86, 0.4))
	for entry: Variant in reward.get("items", []):
		if entry is Dictionary:
			_line("%s ×%d" % [
				str((entry as Dictionary).get("name", "?")),
				int((entry as Dictionary).get("amount", 1)),
			], Color(0.8, 0.9, 0.8))
	if gold <= 0 and (reward.get("items", []) as Array).is_empty():
		_line("(no drops this time)", Color(0.7, 0.74, 0.82))


func _build_shell(failed: bool = false) -> void:
	for child: Node in get_children():
		child.queue_free()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A dark-red wash for a wipe, the usual dark-blue for a clear.
	backdrop.color = Color(0.11, 0.03, 0.04, 0.80) if failed else Color(0.03, 0.05, 0.09, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 20)
	pad.add_theme_constant_override(&"margin_right", 20)
	pad.add_theme_constant_override(&"margin_top", 18)
	pad.add_theme_constant_override(&"margin_bottom", 18)
	card.add_child(pad)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 10)
	pad.add_child(_content)


func _title(text: String, color: Color = Color(1.0, 0.92, 0.55)) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)


func _line(text: String, color: Color = Color.WHITE, size: int = 13) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)
