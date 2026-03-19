extends NavPanel
## Controls Settings Panel
##
## Containers:
##	Each container must be exported and registered in container_map.
##	Section visibility is controlled via SECTIONS_CONTAINERS using container identifiers.
##
## Options (CheckButton, HSlider, Remap Buttons);
##	Uses metadata to bind UI to settings/actions.
## 
## Metadatas:
## &"property_name";
##	Used by CheckButtons and Sliders.
##	Maps the control value to ClientState.settings.
## 
## &"action_name";
##	Used by remap buttons.
##	Defines which input action will be reassigned at runtime.


const SECTIONS_CONTAINERS: Dictionary[StringName, Array] = {
	&"mouse_keyboard": [&"kb_mouse", &"movement", &"actions"],
	&"gamepad": [&"gamepad", &"movement", &"aim", &"actions"],
	&"touch": [&"touch"]
}

@export_group("Containers")
@export var kb_mouse_container: VBoxContainer
@export var gamepad_container: VBoxContainer
@export var touch_container: VBoxContainer

@export var movement_container: VBoxContainer
@export var aim_container: VBoxContainer
@export var actions_container: VBoxContainer

@export_category("Buttons")
@export var check_buttons: Array[CheckButton]
@export var hsliders: Array[HSlider]
@export var section_switch_group: ButtonGroup
@export var remap_button_group: ButtonGroup

var container_map: Dictionary[StringName, VBoxContainer]

var current_section: StringName
var active_remap_button: Button


func _ready() -> void:
	set_process_unhandled_input(false)
	_bind_controls.call_deferred()

	container_map = {
		&"kb_mouse": kb_mouse_container,
		&"gamepad": gamepad_container,
		&"touch": touch_container,
		&"movement": movement_container,
		&"aim": aim_container,
		&"actions": actions_container,
	}


func _unhandled_input(event: InputEvent) -> void:
	if not active_remap_button:
		set_process_unhandled_input(false)
		return

	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		active_remap_button.button_pressed = false
		return
	
	if not _is_event_valid(event):
		## Todo: display popup warning that event is not valid.
		active_remap_button.button_pressed = false
		return

	get_viewport().set_input_as_handled()

	var action_name: StringName = active_remap_button.get_meta(&"action_name")
	var event_available: Array = InputComponent.is_event_available(event)
	if not event_available[0] and event_available[1] != action_name:
		## Todo: display popup warning that event is being used in action_name
		active_remap_button.button_pressed = false
		return

	ClientState.settings.set_value(current_section, action_name, event)
	active_remap_button.button_pressed = false


func enter(_payload: Dictionary = {}) -> void:
	var target_section: StringName = _get_input_type_as_string()
	for button: Button in section_switch_group.get_buttons():
		if not button.has_meta(&"section_name"): continue

		var section_name: StringName = button.get_meta(&"section_name")
		if section_name == target_section:
			current_section = section_name
			show_section(current_section)
			button.set_pressed_no_signal(true)
			break


func _bind_controls() -> void:
	for slider: HSlider in hsliders:
		slider.drag_ended.connect(_on_value_changed.bind(slider))

	for check_button: CheckButton in check_buttons:
		check_button.pressed.connect(_on_value_changed.bind(check_button))

	for remap_button: Button in remap_button_group.get_buttons():
		remap_button.toggled.connect(_on_remap_button_toggled.bind(remap_button))

	section_switch_group.pressed.connect(_on_section_button_pressed)


func _on_value_changed(value_changed: bool, node: Control) -> void:
	if not node.has_meta(&"property_name"): return
	var property_name: StringName = node.get_meta(&"property_name")
	var value: Variant
	
	if node is Slider and value_changed:
		value = node.value
	elif node is CheckButton:
		value = node.button_pressed
	
	ClientState.settings.set_value(current_section, property_name, value)


func _on_remap_button_toggled(toggled_on: bool, button: Button) -> void:
	if not button.has_meta(&"action_name"): return

	if toggled_on:
		active_remap_button = button
		button.text = "Awaiting Input..."
		button.grab_focus()
	else:
		active_remap_button = null
		_update_remap_button_text(button)
		button.release_focus()

	set_process_unhandled_input(toggled_on)


func _on_section_button_pressed(button: Button) -> void:
	if button.has_meta(&"section_name"):
		current_section = button.get_meta(&"section_name")
		if SECTIONS_CONTAINERS.has(current_section):
			show_section(current_section)


func _get_sections_container(section: StringName) -> Array[VBoxContainer]:
	var result: Array[VBoxContainer] = []
	if not SECTIONS_CONTAINERS.has(section): return result

	for container_name: StringName in SECTIONS_CONTAINERS[section]:
		if container_map.has(container_name):
			result.append(container_map[container_name])
	
	return result


func _update_buttons(section: StringName) -> void:
	var settings: Dictionary = ClientState.settings.data
	if not settings.has(section): return
	
	for check_button: CheckButton in check_buttons:
		var property_name: StringName = check_button.get_meta(&"property_name", &"none")
		if settings[section].has(property_name):
			check_button.set_pressed_no_signal(settings[section][property_name])

	for slider: HSlider in hsliders:
		var property_name: StringName = slider.get_meta(&"property_name", &"none")
		if settings[section].has(property_name):
			slider.set_value_no_signal(settings[section][property_name])

	for remap_button: Button in remap_button_group.get_buttons():
		_update_remap_button_text(remap_button)


func _update_remap_button_text(button: Button) -> void:
	if button.has_meta(&"action_name"):
		var input_type: InputComponent.InputType = InputComponent.InputType[current_section.to_upper()]
		var current_event: InputEvent = InputComponent.find_action_event(button.get_meta(&"action_name"), input_type)
		# Todo: display icons instead of input key text.
		if current_event:
			button.text = current_event.as_text()
		else:
			button.text = "Unbound"


func _get_input_type_as_string() -> StringName:
	var inputs_key: Array = InputComponent.InputType.keys()
	return StringName(inputs_key[ClientState.input_type]).to_lower()


func _is_event_valid(event: InputEvent) -> bool:
	if event is InputEventKey and current_section == &"mouse_keyboard":
		return true
	elif (event is InputEventJoypadButton or event is InputEventJoypadMotion) and current_section == &"gamepad":
		return true
	return false


func show_section(section: StringName) -> void:
	var sections_container: Array[VBoxContainer] = _get_sections_container(section)
	hide_all_containers(sections_container)
	_update_buttons(section)


func hide_all_containers(except: Array = []) -> void:
	for container: VBoxContainer in container_map.values():
		container.visible = except.has(container)