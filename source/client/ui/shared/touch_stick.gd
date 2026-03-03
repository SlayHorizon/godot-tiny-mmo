@icon("res://assets/node_icons/green/icon_target_2.png")
class_name TouchStick
extends Control

enum StickMode {
	FIXED,
	DYNAMIC
}

@export_category("Joystick")
@export var base: TextureRect
@export var handle: TextureRect
@export_group("Joystick Settings")
@export var stick_mode: StickMode
@export_range(0.0, 0.9) var dead_zone: float = 0.1
@export_range(0, 200) var handle_radius: float = 75.0

@export_category("Input Settings")
@export var use_input_actions: bool
@export_group("Actions Name")
@export var action_up: StringName
@export var action_down: StringName
@export var action_left: StringName
@export var action_right: StringName

var enabled: bool:
	set(value):
		enabled = value
		if is_inside_tree():
			set_process_input(value)

var direction: Vector2

var _touch_index: int = -1
var _is_dynamic_active: bool
var _base_default_pos: Vector2


func _ready() -> void:
	assert(is_instance_valid(base), "TouchStick: no base found.")
	assert(base.get_parent() == self, "TouchStick: base must be a parent of TouchStick.")
	assert(is_instance_valid(handle), "TouchStick: no handle found.")
	assert(handle.get_parent() == base, "TouchStick: handle must be a parent of base.")

	self.resized.connect(func() -> void:
		_base_default_pos = base.global_position
		base.global_position = _base_default_pos
	)
	_base_default_pos = base.global_position

	# Make sure to not interrupt mouse inputs.
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.is_pressed() and _is_touch_inside_area(event.position):
			_touch_index = event.index
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()
		elif event.index == _touch_index:
			_reset_joystick()
			get_viewport().set_input_as_handled()
	
	if event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()


func _update_joystick(touch_pos: Vector2) -> void:
	if stick_mode == StickMode.FIXED:
		_move_handle(touch_pos)
	elif stick_mode == StickMode.DYNAMIC:
		if not _is_dynamic_active:
			_is_dynamic_active = true
			base.global_position = touch_pos - base.size / 2
		_move_handle(touch_pos)

	if use_input_actions:
		_handle_input_actions()


func _handle_input_actions() -> void:
	var input_actions: Dictionary[StringName, float] = {
		action_up: max(-direction.y, 0),
		action_down: max(direction.y, 0),
		action_left: max(-direction.x, 0),
		action_right: max(direction.x, 0)
	}

	for action_name: StringName in input_actions.keys():
		var strengh: float = input_actions[action_name]
		if strengh > 0:
			Input.action_press(action_name, strengh)
		else:
			Input.action_release(action_name)


func _is_touch_inside_area(touch_pos: Vector2) -> bool:
	var is_inside_area: bool
	if stick_mode == StickMode.FIXED:
		is_inside_area = base.get_global_rect().has_point(touch_pos)
	elif stick_mode == StickMode.DYNAMIC:
		is_inside_area = self.get_global_rect().has_point(touch_pos)
	
	return is_inside_area


func _move_handle(touch_pos: Vector2) -> void:
	var base_center: Vector2 = base.global_position + base.size / 2
	var lenght: Vector2 = (touch_pos - base_center).limit_length(handle_radius)

	direction = lenght.normalized()
	handle.position = (base.size / 2) - (handle.size / 2) + lenght


func _reset_joystick() -> void:
	_touch_index = -1
	_is_dynamic_active = false
	direction = Vector2.ZERO

	base.global_position = _base_default_pos
	handle.position = (base.size / 2) - (handle.size / 2)

	if use_input_actions:
		for action_name: StringName in [action_up, action_down, action_left, action_right]:
			if Input.is_action_pressed(action_name):
				Input.action_release(action_name)
