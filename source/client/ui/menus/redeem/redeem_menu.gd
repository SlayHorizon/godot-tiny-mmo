extends Control
## Small centered popup to redeem a code — from the HUD launcher's "Redeem" tile.
## Two states in one card: an input step, then a "You received" result step the
## player dismisses at their own pace (a toast was too fleeting for a reward list).
## Errors show inline on the input step so the player can fix a typo and retry.
## Built in code like the other compact dialogs (see attribute_reset_menu).

const CARD_WIDTH: float = 360.0

var _body: VBoxContainer
var _busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_frame()
	_show_input_state()
	visibility_changed.connect(_on_visibility_changed)


## Static frame (backdrop + centered card). The card body is rebuilt per state.
func _build_frame() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.4)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 16)
	pad.add_theme_constant_override(&"margin_right", 16)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 12)
	pad.add_child(_body)


func _on_visibility_changed() -> void:
	if visible:
		_show_input_state()


func _clear_body() -> void:
	for child: Node in _body.get_children():
		child.queue_free()


func _make_title(text: String) -> Label:
	var title: Label = Label.new()
	title.text = text
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	title.add_theme_font_size_override(&"font_size", 20)
	return title


## Input step — title, code field, optional inline error, Redeem + Close.
func _show_input_state(error: String = "") -> void:
	_busy = false
	_clear_body()
	_body.add_child(_make_title("Redeem Code"))

	var field: LineEdit = LineEdit.new()
	field.placeholder_text = "Enter a code"
	field.max_length = 32
	field.text_submitted.connect(func(_t: String) -> void: _on_redeem(field))
	_body.add_child(field)

	if not error.is_empty():
		var err: Label = Label.new()
		err.text = error
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.add_theme_color_override(&"font_color", Color(0.95, 0.6, 0.55))
		_body.add_child(err)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(buttons)

	var redeem: Button = Button.new()
	redeem.text = "Redeem"
	redeem.custom_minimum_size = Vector2(150, 40)
	redeem.pressed.connect(_on_redeem.bind(field))
	buttons.add_child(redeem)

	var close: Button = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(110, 40)
	close.pressed.connect(hide)
	buttons.add_child(close)

	field.grab_focus.call_deferred()


## Result step — persistent "You received" list the player closes when ready.
func _show_result_state(lines: PackedStringArray) -> void:
	_clear_body()
	_body.add_child(_make_title("Code redeemed!"))

	var received: Label = Label.new()
	received.text = "You received:"
	received.add_theme_color_override(&"font_color", Color(0.85, 0.86, 0.92))
	_body.add_child(received)

	for line: String in lines:
		var row: Label = Label.new()
		row.text = "•  " + line
		row.add_theme_color_override(&"font_color", Color(0.95, 0.92, 0.78))
		_body.add_child(row)

	var close: Button = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(hide)
	_body.add_child(close)


func _on_redeem(field: LineEdit) -> void:
	if _busy:
		return
	var code: String = field.text.strip_edges()
	if code.is_empty():
		return
	_busy = true
	field.editable = false

	var result: Array = await Client.request_data_await(
		&"redeem.code", {"code": code}, InstanceClient.current.name
	)
	if not is_inside_tree() or not visible:
		return
	if result[1] != OK:
		_show_input_state("Couldn't reach the server. Try again.")
		return
	var data: Dictionary = result[0]
	if bool(data.get("ok", false)):
		var lines: PackedStringArray = PackedStringArray()
		for r: Variant in (data.get("rewards", []) as Array):
			lines.append(RewardFormat.describe(r as Dictionary))
		_show_result_state(lines)
	else:
		_show_input_state(_humanize(str(data.get("reason", ""))))


func _humanize(reason: String) -> String:
	match reason:
		"unknown": return "That code doesn't exist."
		"already": return "You've already redeemed this code on this character."
		"expired": return "This code has expired."
		"rate_limited": return "Too many tries — wait a moment and try again."
		"misconfigured": return "This code isn't set up correctly. Please report it."
		_: return "Couldn't redeem that code."
