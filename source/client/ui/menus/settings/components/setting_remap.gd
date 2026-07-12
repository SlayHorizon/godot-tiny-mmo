class_name SettingRemapWidget
extends SettingWidget


## Ignore mouse events this long after capture starts, so the click that
## pressed the capture button can't bind itself.
const MOUSE_ARM_DELAY_MS: int = 250
## How long the "Used by X" conflict message stays on the button.
const CONFLICT_FLASH_S: float = 1.2

var _capture_started_ms: int
var _flash_id: int


func _ready() -> void:
	assert(is_instance_valid(controller))
	assert(InputMap.has_action(setting_property))

	if is_instance_valid(setting_label):
		setting_label.text = _action_display_name(setting_property)
	controller.toggled.connect(_on_controller_value_changed)
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: return

	if event is InputEventKey and event.pressed:
		# Escape cancels the capture; Backspace/Delete unbinds the action.
		if event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			controller.button_pressed = false
			return
		if event.physical_keycode == KEY_BACKSPACE or event.physical_keycode == KEY_DELETE:
			get_viewport().set_input_as_handled()
			controller.button_pressed = false
			ClientState.settings.set_value(setting_section, setting_property, "")
			return

	# Bind on presses only; the arm delay keeps the click that opened the
	# capture from binding itself.
	if event is InputEventMouseButton:
		if Time.get_ticks_msec() - _capture_started_ms < MOUSE_ARM_DELAY_MS: return
		if not event.pressed: return
	if event is InputEventKey and not event.pressed:
		return
	# Stick drift guard: only a deliberate push binds an axis.
	if event is InputEventJoypadMotion and absf(event.axis_value) < 0.5:
		return

	if not _is_event_valid(event):
		controller.button_pressed = false
		return

	get_viewport().set_input_as_handled()
	var event_available: Array = InputComponent.is_event_available(event)
	if not event_available[0] and event_available[1] != setting_property:
		controller.button_pressed = false
		_flash_conflict(event_available[1])
		return

	var value: String = InputComponent.event_to_keycode(event)
	ClientState.settings.set_value(setting_section, setting_property, value)
	controller.button_pressed = false


func _on_controller_value_changed(toggled_on: bool = false) -> void:
	if toggled_on:
		_capture_started_ms = Time.get_ticks_msec()
		controller.text = "Press any input..."
		controller.grab_focus()
	else:
		_load_defaults()
		controller.release_focus()

	set_process_input(toggled_on)


func _load_defaults() -> void:
	if not is_instance_valid(controller): return
	_flash_id += 1
	var keycode: Variant = ClientState.settings.get_value(setting_section, setting_property)
	if keycode is String and not keycode.is_empty():
		controller.text = InputComponent.keycode_to_display(keycode)
	else:
		controller.text = "Unbound"


func _is_event_valid(event: InputEvent) -> bool:
	if setting_section == &"mouse_keyboard":
		return event is InputEventKey or event is InputEventMouseButton

	if setting_section == &"gamepad":
		return event is InputEventJoypadButton or event is InputEventJoypadMotion

	return false


# Briefly shows which action already owns the pressed input, then restores
# the bound-key text (unless something newer touched the button since).
func _flash_conflict(taken_by: StringName) -> void:
	if not is_instance_valid(controller): return
	controller.text = "Used by %s" % _action_display_name(taken_by)
	_flash_id += 1
	var flash_id: int = _flash_id
	get_tree().create_timer(CONFLICT_FLASH_S).timeout.connect(func() -> void:
		if _flash_id == flash_id:
			_load_defaults()
	)


static func _action_display_name(action_name: StringName) -> String:
	return String(action_name).replace("player", "").replace("_", " ").capitalize().strip_edges()
