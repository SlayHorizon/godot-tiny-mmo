class_name SettingRemapWidget
extends SettingWidget


func _ready() -> void:
	assert(is_instance_valid(controller))
	assert(InputMap.has_action(setting_property))

	if is_instance_valid(setting_label):
		setting_label.text = setting_property.replace("player", "").replace("_", " ").capitalize()
	controller.toggled.connect(_on_controller_value_changed)
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: return
	if event is InputEventMouseButton:
		controller.button_pressed = false
		return
	
	if not _is_event_valid(event):
		controller.button_pressed = false 
		return

	get_viewport().set_input_as_handled()
	var event_available: Array = InputComponent.is_event_available(event)
	if not event_available[0] and event_available[1] != setting_property:
		controller.button_pressed = false
		return
	
	var value: String = InputComponent.event_to_keycode(event)
	ClientState.settings.set_value(setting_section, setting_property, value)
	controller.button_pressed = false


func _on_controller_value_changed(toggled_on: bool = false) -> void:
	if toggled_on:
		controller.text = "Awaiting Input..."
		controller.grab_focus()
	else:
		_load_defaults()
		controller.release_focus()

	set_process_input(toggled_on)


func _load_defaults() -> void:
	if not is_instance_valid(controller): return
	var event: Variant = ClientState.settings.get_value(setting_section, setting_property)
	controller.text = event if event else "Unbound"


func _is_event_valid(event: InputEvent) -> bool:
	if event is InputEventKey and setting_section == &"mouse_keyboard": 
		return true

	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and setting_section == &"gamepad":
		return true

	return false
