extends Control
## Name-change dialog — reached from an NPC's NameChangeInteraction. One
## LineEdit with live validation (the SAME CredentialsUtils rules the gateway
## uses at character creation, so hints here and server errors match by
## construction); confirm fires the server-authoritative name.change handler.
## Same compact card as the NPC dialogue.
##
## open() arg: the gold cost (int).

const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")

const HINT_COLOR: Color = Color(0.62, 0.64, 0.72)
const ERROR_COLOR: Color = Color(1.0, 0.45, 0.45)

var _cost: int = 0
var _name_edit: LineEdit
var _hint_label: Label
var _confirm_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(arg: Variant) -> void:
	for child: Node in get_children():
		child.queue_free()
	_cost = int(arg) if arg != null else 0

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.4)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 16)
	pad.add_theme_constant_override(&"margin_right", 16)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	pad.add_child(box)

	var title: Label = Label.new()
	title.text = "Change name"
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	title.add_theme_font_size_override(&"font_size", 20)
	box.add_child(title)

	var body: Label = Label.new()
	body.text = "Pick a new name for your character.\nThis costs %d gold." % _cost
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", Color(0.85, 0.86, 0.92))
	box.add_child(body)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "New name"
	_name_edit.max_length = CredentialsUtils.USERNAME_MAX_LEN
	_name_edit.custom_minimum_size = Vector2(0, 38)
	_name_edit.text_changed.connect(_on_text_changed)
	_name_edit.text_submitted.connect(_on_text_submitted)
	box.add_child(_name_edit)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override(&"font_size", 12)
	box.add_child(_hint_label)
	_set_hint(_default_hint(), false)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)

	_confirm_button = Button.new()
	_confirm_button.text = "Change name (%d g)" % _cost
	_confirm_button.custom_minimum_size = Vector2(170, 40)
	_confirm_button.disabled = true
	_confirm_button.pressed.connect(_on_confirm)
	buttons.add_child(_confirm_button)

	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(110, 40)
	cancel.pressed.connect(hide)
	buttons.add_child(cancel)

	_name_edit.grab_focus()


func _default_hint() -> String:
	return "%d-%d characters. Letters, digits and _ only." % [
		CredentialsUtils.USERNAME_MIN_LEN, CredentialsUtils.USERNAME_MAX_LEN
	]


func _set_hint(text: String, is_error: bool) -> void:
	_hint_label.text = text
	_hint_label.add_theme_color_override(&"font_color", ERROR_COLOR if is_error else HINT_COLOR)


func _on_text_changed(new_text: String) -> void:
	var trimmed: String = new_text.strip_edges()
	if trimmed.is_empty():
		_set_hint(_default_hint(), false)
		_confirm_button.disabled = true
		return
	var check: Dictionary = CredentialsUtils.validate_username(trimmed)
	if check.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		_set_hint(str(check.get("message", "")), true)
		_confirm_button.disabled = true
		return
	_set_hint(_default_hint(), false)
	_confirm_button.disabled = false


func _on_text_submitted(_text: String) -> void:
	if not _confirm_button.disabled:
		_on_confirm()


func _on_confirm() -> void:
	_confirm_button.disabled = true
	var new_name: String = _name_edit.text.strip_edges()
	var result: Array = await Client.request_data_await(
		&"name.change", {"name": new_name}, InstanceClient.current.name
	)
	if result[1] != OK:
		hide()
		return
	var data: Dictionary = result[0]
	if data.get("ok", false):
		# The synced :display_name also reaches us, but apply locally too so the
		# swap is instant (same pattern as the wardrobe's skin_id).
		if ClientState.local_player != null and is_instance_valid(ClientState.local_player):
			ClientState.local_player.display_name = str(data.get("name", new_name))
		Toaster.toast("Name changed to %s." % str(data.get("name", new_name)))
		hide()
		return
	match str(data.get("reason", "")):
		"gold":
			_set_hint("Not enough gold (%d g needed)." % _cost, true)
		"same":
			_set_hint("That's already your name.", true)
		"invalid":
			_set_hint(str(data.get("message", "Invalid name.")), true)
		_:
			Toaster.toast("Couldn't change your name right now.")
			hide()
	if not str(data.get("reason", "")).is_empty() and visible:
		_confirm_button.disabled = false
