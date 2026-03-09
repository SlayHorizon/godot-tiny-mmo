class_name InputComponent
extends Node2D


enum InputType {
	MOUSE_AND_KEYBOARD,
	GAMEPAD,
	TOUCH
}


signal input_changed(input_type: InputType)


var is_gamepad_enabled: bool:
	get: return input_type == InputType.GAMEPAD

var is_touch_screen_enabled: bool:
	get: return input_type == InputType.TOUCH

var is_mouse_onscreen: bool:
	get: return (is_mouse_enabled and _mouse_in_game and _windows_focus)

var is_keyboard_enabled: bool
var is_mouse_enabled: bool
var input_type: InputType

var _windows_focus: bool = true
var _mouse_in_game: bool = true


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		set_input_type(InputType.MOUSE_AND_KEYBOARD)
		is_keyboard_enabled = true
	
	elif event is InputEventMouseMotion and not is_mouse_enabled:
		set_input_type(InputType.MOUSE_AND_KEYBOARD)
		is_mouse_enabled = true

	elif event is InputEventMouseButton and event.is_pressed():
		set_input_type(InputType.MOUSE_AND_KEYBOARD)
		is_mouse_enabled = true
	
	elif event is InputEventJoypadButton and event.is_pressed():
		set_input_type(InputType.GAMEPAD)

	elif event is InputEventJoypadMotion:
		set_input_type(InputType.GAMEPAD)
	
	elif event is InputEventScreenTouch and event.is_pressed():
		set_input_type(InputType.TOUCH)


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


func set_input_type(type: InputType) -> void:
	if input_type == type: return
	if type != InputType.MOUSE_AND_KEYBOARD:
		is_mouse_enabled = false
		is_keyboard_enabled = false
	
	input_type = type
	input_changed.emit(type)


func get_mouse_position() -> Vector2:
	if is_mouse_onscreen:
		return get_global_mouse_position()
	return Vector2.ZERO


func get_move_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func get_look_direction() -> Vector2:
	var look_dir: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_dir != Vector2.ZERO:
		is_mouse_enabled = false 
		return look_dir
	if is_mouse_enabled:
		return (get_mouse_position() - global_position).normalized()
	return Vector2.ZERO