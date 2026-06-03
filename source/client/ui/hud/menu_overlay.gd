extends Control
## Right-side HUD menu launcher. A themed panel of entries that open the game's
## menus, built in code and routed through ClientState signals so it stays
## decoupled from the HUD script. A dim backdrop catches click-away taps.
##
## Open it with [method open] (the HUD's Menu button calls this).

## Each entry: label shown, and the menu folder to open. An empty `menu` is the
## special "own profile" entry (routes through player_profile_requested).
const ENTRIES: Array = [
	{"label": "Profile",     "menu": ""},
	{"label": "Character",   "menu": "character"},
	{"label": "Inventory",   "menu": "inventory"},
	{"label": "Guild",       "menu": "guild"},
	{"label": "Leaderboard", "menu": "leaderboard"},
	{"label": "Friends",     "menu": "friends"},
	{"label": "Settings",    "menu": "settings"},
]

var _panel: PanelContainer


func _ready() -> void:
	_build()
	hide()


func _build() -> void:
	# Dim backdrop — covers the screen so a tap outside the panel closes it and
	# the game underneath doesn't receive the click.
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.5)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(dim)

	# Right-docked themed card.
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -220.0
	_panel.offset_right = -12.0
	_panel.offset_top = 12.0
	_panel.offset_bottom = -12.0
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 6)
	margin.add_child(vbox)

	var header: Label = Label.new()
	header.text = "Menu"
	header.add_theme_font_size_override(&"font_size", 18)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	for entry: Dictionary in ENTRIES:
		var btn: Button = Button.new()
		btn.text = "▸  " + str(entry["label"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_entry_pressed.bind(str(entry["menu"])))
		vbox.add_child(btn)

	# Push Close to the bottom of the card.
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(close)
	vbox.add_child(close_button)


func _on_entry_pressed(menu_name: String) -> void:
	close()
	if menu_name.is_empty():
		ClientState.player_profile_requested.emit(0)  # 0 = own profile
	else:
		ClientState.open_menu_requested.emit(StringName(menu_name), null)


## Shows the launcher with a quick fade. Called by the HUD's Menu button.
func open() -> void:
	show()
	modulate.a = 0.0
	create_tween().tween_property(self, ^"modulate:a", 1.0, 0.15)


func close() -> void:
	hide()
