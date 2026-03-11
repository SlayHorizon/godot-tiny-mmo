@icon("res://assets/node_icons/green/icon_target_2.png")
class_name TouchStick
extends Control


enum StickMode {
	## Touch is detected only inside the base area.
	FIXED,
	## Touch is detected outside the base area. also move the base to the touch position.
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
## The joystick base. Must be a child of this node.
@export var base: TextureRect
## The joystick handle. Must be a child of the base.
@export var handle: TextureRect

@export_group("Joystick Settings")
## Joystick behavior in relation to touch inputs.[br][br]
## [b][color=yellow]IMPORTANT:[/color][/b][br]
## The area of the base defines the touch area for [b]FIXED[/b] mode to work. [br]
## The area of this TouchStick node defines the touch area for [b]DYNAMIC[/b] mode to work.
@export var stick_mode: StickMode
## Defines how the joystick handle direction is visually snapped. [br]
## [b]Note:[/b] This affects visuals only and does not change the actual input direction.
@export_range(0, 32, 1) var snap_directions: int = 0
## When enabled, the handle snaps to the maximum radius in the current snapped direction. [br]
## [b]Note:[/b] This affects visuals only.
@export var snap_handle: bool
## Maximum distance to trigger movement.
@export_range(0.0, 0.9) var deadzone: float = 0.2
## The max distance the handle can move from the center of the base.
@export_range(0, 200) var handle_radius: float = 75.0

@export_category("Input Settings")
## Trigger [b][color=yellow]InputMap[/color][/b] actions when enabled.
@export var use_input_actions: bool
@export_group("Actions Name")
@export var action_up: StringName ## Negative_Y
@export var action_down: StringName ## Positive_Y
@export var action_left: StringName ## Negative_X
@export var action_right: StringName ## Positive_X

## Stick direction.
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

	if use_input_actions:
		for action_name: StringName in [action_up, action_down, action_left, action_right]:
			if not InputMap.has_action(action_name):
				use_input_actions = false
				printerr("TouchStick: input action disabled. Couldn't find action: ", action_name)
				break

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

	if strength < deadzone:
		direction = Vector2.ZERO
		offset = Vector2.ZERO
	else:
		direction = offset.normalized()
		var snap_dir: Vector2 = _snap_direction(direction)
		var distance: float = handle_radius if snap_handle else handle_radius * strength
		offset = snap_dir * distance

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


func _snap_direction(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO or snap_directions < 1: 
		return dir

	var step: float = TAU / float(snap_directions)
	var snapped_angle: float = round(dir.angle() / step) * step

	return Vector2.RIGHT.rotated(snapped_angle)


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