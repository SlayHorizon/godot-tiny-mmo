extends Control
## Shown when a dungeon run is COMPLETED — dungeon name, completion time, reward,
## and a note that the party is being returned to town. Opened via
## open_menu_requested(&"dungeon_recap", recap_dict). Auto-closes when the server
## ejects the party (after eject_in seconds), or on Close.

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(data: Dictionary) -> void:
	_build_shell()

	_title("Dungeon Cleared!")
	_line(str(data.get("dungeon", "Dungeon")), Color(0.8, 0.85, 1.0), 16)
	_line("Completion time: %ds" % int(data.get("seconds", 0)))
	_line("Reward: kill loot + a completion bonus")  # placeholder until the end-chest
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


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.09, 0.78)
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


func _title(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.55))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)


func _line(text: String, color: Color = Color.WHITE, size: int = 13) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)
