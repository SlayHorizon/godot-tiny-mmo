extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.


signal local_player_ready(local_player: LocalPlayer)
signal player_profile_requested(id: int)
signal dm_requested(id: int)
## Emitted whenever the active input type changes. [br]
## [b]Example[/b]: switching from keyboard to gamepad.
signal input_changed(input_type: InputComponent.InputType)

var local_player: LocalPlayer
var player_id: int
var active_guild_id: int
var stats: DataDict = DataDict.new()
var settings: Settings = Settings.new()
var quick_slots: DataDict = DataDict.new()
var guilds: DataDict = DataDict.new()

var input_type: InputComponent.InputType:
	set(value):
		input_type = value
		input_changed.emit(value)


func _ready() -> void:
	if not OS.has_feature("client"):
		queue_free()
	Client.subscribe(&"player_id.set", func(payload: Dictionary):
		player_id = payload.get("player_id", 0))
	Client.subscribe(&"active_guild_id.set", func(payload: Dictionary):
		active_guild_id = payload.get("active_guild_id", 0))
	Client.subscribe(&"stats.get", func(data: Dictionary):
		stats.data.merge(data, true)
	)

	settings.load_file()


class DataDict:
	signal data_changed(property: Variant, value: Variant)
	
	var data: Dictionary
	
	
	func _set(property: StringName, value: Variant) -> bool:
		if property == &"data":
			return false
		data[property] = value
		data_changed.emit(property, value)
		return true
	
	
	func set_key(key: Variant, value: Variant) -> void:
		data.set(key, value)
		data_changed.emit(key, value)
	
	
	func get_key(property: Variant, default: Variant = null) -> Variant:
		return data.get(property, default)


class Settings:
	const SETTINGS_PATH: String = "user://client_settings.cfg"
	const DEFAULTS_PATH: String = "res://data/config/client_default_settings.cfg"

	signal setting_changed(section: StringName, property: StringName, new_value: Variant)

	var data: Dictionary


	func load_file() -> void:
		var defaults: Dictionary = ConfigFileUtils.load_file_with_defaults(DEFAULTS_PATH, {})
		data = ConfigFileUtils.load_file_with_defaults(SETTINGS_PATH, defaults)


	func save() -> void:
		ConfigFileUtils.save_sections(data, SETTINGS_PATH)
	

	func get_value(section: StringName, property: StringName) -> Variant:
		return data.get(section, {}).get(property)


	func set_value(section: StringName, property: StringName, value: Variant) -> void:
		data[section][property] = value
		setting_changed.emit(section, property, value)
		save()


	func apply_all() -> void:
		for section: StringName in data:
			for property: StringName in data[section]:
				apply(section, property, data[section][property])


	func apply(section: StringName, property: StringName, value: Variant) -> void:
		match [section, property]:
			## Gameplay
			[&"gameplay", &"camera_zoom"]:
				ClientState.local_player.set_camera_zoom(clamp(value, 1.0 , 4.0) * Vector2.ONE)
			
			## keyboard mouse
			[&"mouse_keyboard", property]: # Inputs
				if value is InputEventKey or value is InputEventMouseButton:
					var input_type: InputComponent.InputType = InputComponent.InputType[section.to_upper()]
					InputComponent.replace_event(property, value, input_type)
			
			## Gamepad
			[&"gamepad", property]: # Inputs
				if value is InputEventJoypadButton or value is InputEventJoypadMotion:
					var input_type: InputComponent.InputType = InputComponent.InputType[section.to_upper()]
					InputComponent.replace_event(property, value, input_type)
			[&"gamepad", &"deadzone_enter"]:
				ClientState.local_player.controller.stick_deadzone_enter = value
			[&"gamepad", &"deadzone_exit"]:
				ClientState.local_player.controller.stick_deadzone_exit = value
			
			## Touch
			[&"touch", &"dynamic_left_stick"]:
				ClientState.local_player.controller.left_touch_stick.stick_mode = _to_stick_mode(value)
			[&"touch", &"dynamic_right_stick"]:
				ClientState.local_player.controller.right_touch_stick.stick_mode = _to_stick_mode(value)
			[&"touch", &"stick_deadzone"]:
				ClientState.local_player.controller.left_touch_stick.deadzone = value
				ClientState.local_player.controller.right_touch_stick.deadzone = value


	func _to_stick_mode(value: bool) -> TouchStick.StickMode:
		return TouchStick.StickMode.DYNAMIC if value else TouchStick.StickMode.FIXED
