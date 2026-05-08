extends NavPanel


@export var input_type_title: Label
@export var settings_containers: Array[SettingsContainer]


func enter(payload: Dictionary = {}) -> void:
	var input_type: String = payload.get("input_type", "MOUSE_KEYBOARD")
	_update_containers_visibility(input_type)
	_update_remap_buttons(input_type.to_lower())
	if is_instance_valid(input_type_title):
		input_type_title.text = input_type.replace("_", " ").capitalize()


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
