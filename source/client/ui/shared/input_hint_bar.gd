class_name InputHintBar
extends HBoxContainer
## Bottom input-hint bar (BotW-style): "[glyph] Verb" pairs for the current
## input device. Menus feed one hint set per device; the bar swaps on
## ClientState.input_changed and stays hidden for devices with no hints —
## touch in particular (you tap what you see, and phone height is precious).
##
## Usage:
## [codeblock]
## var bar := InputHintBar.new()
## bar.set_hints({
##     InputComponent.InputType.MOUSE_KEYBOARD: [["Esc", "Close"]],
##     InputComponent.InputType.GAMEPAD: [["LB/RB", "Category"], ["B", "Close"]],
## })
## body.add_child(bar)
## [/codeblock]

const GLYPH_FONT_SIZE: int = 12
const VERB_COLOR: Color = Color(0.62, 0.66, 0.72)

## InputComponent.InputType -> Array of [glyph: String, verb: String] pairs.
var _hints: Dictionary


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override(&"separation", 14)
	ClientState.input_changed.connect(_on_input_changed)
	_rebuild()


## Sets the per-device hint pairs (see class doc) and refreshes the bar.
func set_hints(hints: Dictionary) -> void:
	_hints = hints
	if is_node_ready():
		_rebuild()


func _on_input_changed(_input_type: InputComponent.InputType) -> void:
	_rebuild()


func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	var device_hints: Array = _hints.get(ClientState.input_type, [])
	visible = not device_hints.is_empty()
	for hint: Array in device_hints:
		add_child(_make_hint(str(hint[0]), str(hint[1])))


func _make_hint(glyph: String, verb: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 5)
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = &"SettingCell"
	var glyph_label: Label = Label.new()
	glyph_label.text = glyph
	glyph_label.add_theme_font_size_override(&"font_size", GLYPH_FONT_SIZE)
	chip.add_child(glyph_label)
	var verb_label: Label = Label.new()
	verb_label.text = verb
	verb_label.add_theme_font_size_override(&"font_size", GLYPH_FONT_SIZE)
	verb_label.add_theme_color_override(&"font_color", VERB_COLOR)
	row.add_child(chip)
	row.add_child(verb_label)
	return row
