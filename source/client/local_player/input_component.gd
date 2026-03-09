class_name InputComponent
extends Node2D


enum InputType {
	MOUSE_KEYBOARD,
	GAMEPAD,
	TOUCH
}


signal input_changed(input_type: InputType)


@export var enabled: bool:
	set(value):
		enabled = value
		set_process_input(value)

@export var node_owner: Node2D

var input_type: InputType

var is_keyboard_enabled: bool
var is_mouse_enabled: bool

var is_gamepad_enabled: bool:
	get: return input_type == InputType.GAMEPAD

var is_touch_screen_enabled: bool:
	get: return input_type == InputType.TOUCH

var is_mouse_onscreen: bool:
	get: return (is_mouse_enabled and _mouse_in_game and _windows_focus)

var _windows_focus: bool = true
var _mouse_in_game: bool = true


func _ready() -> void:
	if DisplayServer.is_touchscreen_available():
		_set_input_type(InputType.TOUCH)
	if not node_owner: 
		node_owner = self
	set_process_input(enabled)


# Deals with input changing for UI.
func _input(event: InputEvent) -> void:
	if not _is_event_relevant(event): return

	match event.get_class():
		"InputEventKey", "InputEventMouseButton", "InputEventMouseMotion":
			_set_input_type(InputType.MOUSE_KEYBOARD)
			if event is InputEventKey: is_keyboard_enabled = true
			is_mouse_enabled = event is InputEventMouseButton or event is InputEventMouseMotion
		"InputEventJoypadButton", "InputEventJoypadMotion":
			_set_input_type(InputType.GAMEPAD)
		"InputEventScreenTouch":
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


func _set_input_type(type: InputType) -> void:
	if input_type == type: return
	if type != InputType.MOUSE_KEYBOARD:
		is_mouse_enabled = false
		is_keyboard_enabled = false
	input_type = type
	input_changed.emit(type)


func _is_event_relevant(event: InputEvent) -> bool:
	if event is InputEventMouseMotion: return not is_mouse_enabled
	if event is InputEventJoypadMotion: return abs(event.axis_value) > 0.5 # Hardcoded deadzone
	return event.is_pressed()


## Returns global mouse position relative to world. If mouse not enabled or mouse offscreen, returns [Vector2.ZERO]
func get_mouse_world_position() -> Vector2:
	if is_mouse_onscreen: 
		return get_global_mouse_position()
	return Vector2.ZERO


## Returns normalized move direction. If no intentional direction, returns [Vector2.ZERO]
func get_move_direction() -> Vector2:
	if not enabled: return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Returns normalized look direction. If no intentional direction, returns [Vector2.ZERO][br]
## - [b]MOUSE[/b] - Cursor direction relative to owner.[br]
## - [b]KEYBOARD[/b] - Arrows key, via InputMap. [br]
## - [b]GAMEPAD[/b] - Right stick, via InputMap.[br]
## - [b]TOUCH[/b] - Virtual joystick, via InputMap. [br]
func get_look_direction() -> Vector2:
	if not enabled: return Vector2.ZERO

	var look_dir: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_dir != Vector2.ZERO: 
		return look_dir
	if is_mouse_onscreen:
		return (get_mouse_world_position() - node_owner.global_position).normalized()
	return Vector2.ZERO