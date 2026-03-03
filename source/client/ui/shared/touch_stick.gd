@icon("res://assets/node_icons/green/icon_target_2.png")
class_name TouchStick
extends Control


enum StickMode {
	FIXED,
	DYNAMIC
}


signal stick_pressed
signal stick_released
signal stick_changed(direction: Vector2)


@export var enabled: bool:
	set(value):
		enabled = value
		set_process_input(enabled)


@export_category("Joystick")
@export var base: TextureRect
@export var handle: TextureRect
@export_group("Joystick Settings")
@export var stick_mode: StickMode
@export_range(0.0, 0.9) var dead_zone: float = 0.2
@export_range(0, 200) var handle_radius: float = 75.0

@export_category("Input Settings")
@export var use_input_actions: bool
@export_group("Actions Name")
@export var action_up: StringName
@export var action_down: StringName
@export var action_left: StringName
@export var action_right: StringName

var direction: Vector2:
	set(value):
		if direction == value: return
		direction = value
		stick_changed.emit(value)

var _touch_index: int = -1
var _is_dynamic_active: bool
var _base_default_pos: Vector2


func _ready() -> void:
	assert(is_instance_valid(base), "TouchStick: no base found.")
	assert(base.get_parent() == self, "TouchStick: base must be a child of TouchStick.")
	
	if is_instance_valid(handle):
		assert(handle.get_parent() == base, "TouchStick: handle must be child of base.")
		handle.mouse_filter = Control.MOUSE_FILTER_IGNORE

	self.resized.connect(func() -> void:
		_base_default_pos = base.global_position
		base.global_position = _base_default_pos	
	)

	# Make sure to not interrupt mouse inputs.
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(enabled)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.is_pressed() and _is_touch_inside_area(event.position):
			_touch_index = event.index
			stick_pressed.emit()
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
	var base_center: Vector2 = base.global_position + base.size / 2
	var offset: Vector2 = (touch_pos - base_center).limit_length(handle_radius)
	var strength: float = offset.length() / handle_radius

	if strength < dead_zone:
		direction = Vector2.ZERO
		offset = Vector2.ZERO
	else:
		direction = offset.normalized()

	match stick_mode:
		StickMode.FIXED:
			_move_handle(offset)
		StickMode.DYNAMIC:
			if not _is_dynamic_active:
				_is_dynamic_active = true
				_move_base(touch_pos)
			_move_handle(offset)

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
		var strength: float = input_actions[action_name]
		if strength > 0:
			Input.action_press(action_name, strength)
		else:
			Input.action_release(action_name)


func _is_touch_inside_area(touch_pos: Vector2) -> bool:
	if stick_mode == StickMode.FIXED:
		return base.get_global_rect().has_point(touch_pos)
	return self.get_global_rect().has_point(touch_pos)


func _move_handle(pos: Vector2) -> void:
	if not is_instance_valid(handle): return
	handle.position = (base.size / 2) - (handle.size / 2) + pos


func _move_base(pos: Vector2) -> void:
	base.global_position = pos - base.size / 2


func _reset_joystick() -> void:
	_touch_index = -1
	_is_dynamic_active = false
	direction = Vector2.ZERO

	base.global_position = _base_default_pos
	if is_instance_valid(handle):
		handle.position = (base.size / 2) - (handle.size / 2)

	if use_input_actions:
		for action_name: StringName in [action_up, action_down, action_left, action_right]:
			if Input.is_action_pressed(action_name):
				Input.action_release(action_name)

	stick_released.emit()