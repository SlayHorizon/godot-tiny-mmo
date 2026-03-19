extends Control


@export var move_stick: TouchStick
@export var shoot_stick: TouchStick
@export var enabled: bool:
	set(value):
		enabled = value
		set_enabled(value)


func _ready() -> void:
	ClientState.settings.setting_changed.connect(_on_setting_changed)
	_apply_settings()
	set_enabled(enabled)


func set_enabled(enable: bool) -> void:
	visible = enable
	if is_instance_valid(move_stick):
		move_stick.enabled = enable
	if is_instance_valid(shoot_stick):
		shoot_stick.enabled = enable


func _on_setting_changed(section: StringName, property: StringName, value: Variant) -> void:
	match [section, property]:
		[&"touch", &"stick_deadzone"]:
			move_stick.deadzone = value
			shoot_stick.deadzone = value
		[&"touch", &"dynamic_right_stick"]:
			shoot_stick.stick_mode = _to_stick_mode(value)
		[&"touch", &"dynamic_left_stick"]:
			move_stick.stick_mode = _to_stick_mode(value)


func _apply_settings() -> void:
	var settings: Dictionary = ClientState.settings.data.get(&"touch", {})
	for property_name: StringName in settings:
		_on_setting_changed(&"touch", property_name, settings[property_name]) 


func _to_stick_mode(value: bool) -> TouchStick.StickMode:
	return TouchStick.StickMode.DYNAMIC if value else TouchStick.StickMode.FIXED