extends NavPanel


@export var input_type_title: Label
@export var input_type_tabs: HBoxContainer
@export var settings_containers: Array[SettingsContainer]


func enter(payload: Dictionary = {}) -> void:
	_build_input_type_tabs()
	if is_instance_valid(input_type_title):
		input_type_title.text = "Controls"
	_select_input_type(payload.get("input_type", _default_input_type()))


## Build one toggle button per input type (Mouse & Keyboard / Touch / Gamepad), once.
func _build_input_type_tabs() -> void:
	if not is_instance_valid(input_type_tabs) or input_type_tabs.get_child_count() > 0:
		return
	var group: ButtonGroup = ButtonGroup.new()
	for input_type: String in InputComponent.InputType.keys():
		var button: Button = Button.new()
		button.text = input_type.replace("_", " & ").capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"FlatButton"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 44)
		button.set_meta(&"input_type", input_type)
		button.pressed.connect(_select_input_type.bind(input_type))
		input_type_tabs.add_child(button)


## The tab shown when Controls is opened without an explicit type.
func _default_input_type() -> String:
	var keys: Array = InputComponent.InputType.keys()
	return String(keys[0]) if not keys.is_empty() else "MOUSE_KEYBOARD"


## Show the settings for [input_type] and reflect the active tab.
func _select_input_type(input_type: String) -> void:
	_update_containers_visibility(input_type)
	_update_remap_buttons(input_type.to_lower())
	if is_instance_valid(input_type_tabs):
		for button: Button in input_type_tabs.get_children():
			if button.get_meta(&"input_type", "") == input_type:
				button.set_pressed_no_signal(true)


func _update_containers_visibility(section: String) -> void:
	if settings_containers.is_empty(): return
	for container: SettingsContainer in settings_containers:
		container.update_visibility(section)


func _update_remap_buttons(section: String) -> void:
	if settings_containers.is_empty(): return
	for container: SettingsContainer in settings_containers:
		for widget: SettingWidget in container.widgets:
			if not widget is SettingRemapWidget: continue
			widget.setting_section = section
