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
var _is_mouse_movemet: bool
var _was_stick_active: bool

#endregion

#region Runtime
func _ready() -> void:
	if DisplayServer.is_touchscreen_available():
		_set_input_type(InputType.TOUCH)

	node_owner = self if not node_owner else node_owner
	set_process_input(enabled)


# Deals with input changing for UI.
func _input(event: InputEvent) -> void:
	if not _is_event_relevant(event): return

	if event is InputEventKey:
		_set_input_type(InputType.MOUSE_KEYBOARD)
		
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		_set_input_type(InputType.MOUSE_KEYBOARD)
		_is_mouse_movemet = true
	
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_set_input_type(InputType.GAMEPAD)

	elif event is InputEventScreenTouch:
		_set_input_type(InputType.TOUCH)


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

#region private helpers
func _set_input_type(type: InputType) -> void:
	if input_type == type: return
	if type == InputType.MOUSE_KEYBOARD:
		_was_stick_active = false
	else:
		_is_mouse_movemet = false
	input_type = type
	input_changed.emit(type)


func _is_event_relevant(event: InputEvent) -> bool:
	if event is InputEventMouseMotion: return is_mouse_and_keyboard_enabled
	if event is InputEventJoypadMotion: return abs(event.axis_value) > 0.5 # Hardcoded deadzone
	return event.is_pressed()


func _get_look_vector() -> Vector2:
	return Input.get_vector("look_left", "look_right", "look_up", "look_down")


func _get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _is_right_stick_active() -> bool:
	return _get_look_vector().length() > 0.5

#endregion

#region public methods
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
	return _get_move_vector().normalized()


## Returns normalized look direction. If no intentional direction, returns [Vector2.ZERO][br]
## - [b]MOUSE[/b] - Cursor direction relative to owner.[br]
## - [b]KEYBOARD[/b] - Arrows key, via InputMap. [br]
## - [b]GAMEPAD[/b] - Right stick, via InputMap.[br]
## - [b]TOUCH[/b] - Virtual joystick, via InputMap. [br]
func get_look_direction() -> Vector2:
	if not enabled: return Vector2.ZERO
	
	var look_dir: Vector2 = _get_look_vector()
	if look_dir != Vector2.ZERO:
		_is_mouse_movemet = false
		return look_dir.normalized()
	
	if _is_mouse_movemet:
		return (get_mouse_world_position() - node_owner.global_position).normalized()
	
	return Vector2.ZERO


## Returns [true] when the user is pressing the attack action event.
func is_attack_pressed() -> bool:
	if not enabled: return false
	if not _is_mouse_movemet:
		return _is_right_stick_active()
	return Input.is_action_pressed(&"action")


## Returns [true] when the user started pressing the attack action event.
func is_attack_just_pressed() -> bool:
	if not enabled: return false
	if not _is_mouse_movemet:
		var active: bool = _is_right_stick_active()
		var just_pressed: bool = active and not _was_stick_active
		if just_pressed: _was_stick_active = active
		return just_pressed
	
	return Input.is_action_just_pressed(&"action")


## Returns [true] when the user stops pressing the attack action event.
func is_attack_just_released() -> bool:
	if not enabled: return false
	if not _is_mouse_movemet:
		var active: bool = _is_right_stick_active()
		var just_released: bool = not active and _was_stick_active
		if just_released: _was_stick_active = active
		return just_released

	return Input.is_action_just_released(&"action")

#endregion