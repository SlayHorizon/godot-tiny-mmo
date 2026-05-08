class_name SettingWidget
extends Control


## The settings section name.
@export var setting_section: StringName:
	set(value):
		setting_section = value
		if is_node_ready():
			_load_defaults()

## The settings property name in the section.
@export var setting_property: StringName:
	set(value):
		setting_property = value
		if is_node_ready():
			_load_defaults()
 
@export var setting_label: Label
## Controller used to set values. can be a button or slider.
@export var controller: Control

@export_group("Slider Settings")
## Set min value, used if controller is a slider.
@export var slider_min_value: float
## Set max value, used if controller is a slider.
@export var slider_max_value: float
@export var steps: float
@export var tick_count: int


func _ready() -> void:
	assert(is_instance_valid(controller), "settings: no controller selected.")
	_load_defaults()

	if is_instance_valid(setting_label):
		setting_label.text = setting_property.replace("_", " ").capitalize()

	if controller is Slider:
		controller.drag_ended.connect(_on_setting_changed)

	elif controller is Button:
		controller.pressed.connect(_on_setting_changed)


func _on_setting_changed(new_value: Variant = null) -> void:
	if controller is Slider:
		new_value = controller.value
	
	elif controller is Button:
		new_value = controller.button_pressed

	if new_value != null:
		ClientState.settings.set_value(setting_section, setting_property, new_value)


func _load_defaults() -> void:
	var value: Variant = ClientState.settings.get_value(setting_section, setting_property)
	if value == null: return

	if controller is Button: 
		controller.text = setting_property.replace("_", " ").capitalize()
		controller.set_pressed_no_signal(value)

	elif controller is Slider:
		controller.tick_count = tick_count
		controller.min_value = slider_min_value
		controller.max_value = slider_max_value
		controller.step = steps 
		controller.set_value_no_signal(value)
