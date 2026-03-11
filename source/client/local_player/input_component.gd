class_name InputComponent
extends Node2D


enum InputType {
	MOUSE_KEYBOARD,
	GAMEPAD,
	TOUCH
}


signal input_changed(input_type: InputType)

#region public variables
@export var enabled: bool:
	set(value):
		enabled = value
		set_process_input(value)

@export var node_owner: Node2D

@export_category("Joystick Settings")
@export var stick_deadzone: float = 0.5

@export_category("Snapping Settings")
@export_range(1, 32) var snap_directions: int = 8
@export_range(0.0, 15.0, 0.5) var snap_tolerance: float = 0.0
@export var snap_for_mouse: bool = false
@export var snap_for_gamepad: bool = true
@export var snap_for_touch: bool = false

var input_type: InputType

var is_mouse_and_keyboard_enabled: bool:
	get: return input_type == InputType.MOUSE_KEYBOARD

var is_gamepad_enabled: bool:
	get: return input_type == InputType.GAMEPAD

var is_touch_screen_enabled: bool:
	get: return input_type == InputType.TOUCH

var is_mouse_onscreen: bool:
	get: return (is_mouse_and_keyboard_enabled and _mouse_in_game and _windows_focus)

#endregion

#region private variables
var _windows_focus: bool = true
var _mouse_in_game: bool = true
var _mouse_aiming: bool
var _was_stick_aim_active: bool

var _last_look_direction: Vector2

#endregion

#region Runtime
func _ready() -> void:
	if DisplayServer.is_touchscreen_available():
		_set_input_type(InputType.TOUCH)

	node_owner = self if not node_owner else node_owner
	set_process_input(enabled)


# Deals with input detection and stick attack sync.
func _input(event: InputEvent) -> void:
	if _is_event_relevant(event):
		if event is InputEventKey:
			_set_input_type(InputType.MOUSE_KEYBOARD)

		elif event is InputEventMouseMotion or event is InputEventMouseButton:
			_set_input_type(InputType.MOUSE_KEYBOARD)
			_mouse_aiming = true
	
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			_set_input_type(InputType.GAMEPAD)

		elif event is InputEventScreenTouch:
			_set_input_type(InputType.TOUCH)
	
	# Gamepad and virtual joystick action event handler.
	if event is InputEventJoypadMotion or event is InputEventScreenTouch or event is InputEventScreenDrag:
		_sync_stick_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_ENTER:
			_mouse_in_game = true
		NOTIFICATION_WM_MOUSE_EXIT:
			_mouse_in_game = false
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_windows_focus = true
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_windows_focus = false

#endregion

#region private
func _sync_stick_event() -> void:
	var active: bool = _is_stick_aiming()
	if active == _was_stick_aim_active: return

	_was_stick_aim_active = active
	if active:
		Input.action_press(&"action")
	else:
		Input.action_release(&"action")


func _set_input_type(type: InputType) -> void:
	if input_type == type: return
	if type != InputType.MOUSE_KEYBOARD:
		_mouse_aiming = false
	input_type = type
	input_changed.emit(type)


func _is_event_relevant(event: InputEvent) -> bool:
	if event is InputEventMouseMotion: return true
	if event is InputEventJoypadMotion: return true
	return event.is_pressed()


func _get_look_raw() -> Vector2:
	return Input.get_vector("look_left", "look_right", "look_up", "look_down")


func _get_move_raw() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _snap_direction(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO or snap_directions < 1: 
		return dir

	var angle: float = dir.angle()
	var step: float = TAU / float(snap_directions)
	var _snapped: float = round(angle / step) * step
	var diff: float = abs(_snapped - angle)

	if diff < deg_to_rad(snap_tolerance):
		return Vector2.RIGHT.rotated(_snapped)

	return dir


func _is_stick_aiming() -> bool:
	return _get_look_raw().length() > stick_deadzone

#endregion

#region public
## Returns global mouse position relative to world. If mouse not enabled or mouse offscreen, returns [Vector2.ZERO]
func get_mouse_world_position() -> Vector2:
	if is_mouse_onscreen: 
		return get_global_mouse_position()
	return Vector2.ZERO


## Returns normalized move direction. If no intentional direction, returns [Vector2.ZERO][br]
## - [b]KEYBOARD[/b] - Arrows key, via InputMap. [br]
## - [b]GAMEPAD[/b] - Right stick, via InputMap.[br]
## - [b]TOUCH[/b] - Virtual joystick, via InputMap. [br]
func get_move_direction() -> Vector2:
	if not enabled: return Vector2.ZERO
	return _get_move_raw().normalized()


## Returns normalized look direction. If no intentional direction, returns [Vector2.ZERO][br]
## - [b]MOUSE[/b] - Cursor direction relative to owner.[br]
## - [b]KEYBOARD[/b] - Arrows key, via InputMap. [br]
## - [b]GAMEPAD[/b] - Right stick, via InputMap.[br]
## - [b]TOUCH[/b] - Virtual joystick, via InputMap. [br]
func get_look_direction() -> Vector2:
	if not enabled: return Vector2.ZERO

	var look_dir: Vector2 = _get_look_raw()
	if look_dir.length() > stick_deadzone: 
		_mouse_aiming = false # Prevent using mouse direction on next getter.
		_last_look_direction = look_dir.normalized()

	if _mouse_aiming:
		_last_look_direction = (get_global_mouse_position() - node_owner.global_position).normalized()
	
	var use_snap: bool = (
		(_mouse_aiming and snap_for_mouse) or
		(is_gamepad_enabled and snap_for_gamepad) or
		(is_touch_screen_enabled and snap_for_touch)
	)

	return _snap_direction(_last_look_direction) if use_snap else _last_look_direction


## Returns [true] when the user is pressing the attack action event.
func is_attack_pressed() -> bool:
	if not enabled: return false
	return Input.is_action_pressed(&"action")


## Returns [true] when the user started pressing the attack action event.
func is_attack_just_pressed() -> bool:
	if not enabled: return false
	return Input.is_action_just_pressed(&"action")


## Returns [true] when the user stops pressing the attack action event.
func is_attack_just_released() -> bool:
	if not enabled: return false
	return Input.is_action_just_released(&"action")

#endregion
