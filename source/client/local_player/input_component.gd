class_name InputComponent
extends Node2D


enum InputType {
	MOUSE_KEYBOARD,
	GAMEPAD,
	TOUCH
}


#region public variables
## Enable or disable the input processing.
@export var enabled: bool:
	set(value):
		enabled = value
		set_process_input(value)

## The node used as a origin for mouse look direction calculation. Default as self if not set.
@export var node_owner: Node2D

@export_category("Joystick Settings")
## Maximum distance the stick need to exceed to be considered active. [br]
## Must be greater than [member stick_deadzone_exit]
@export_range(0, 1.0, 0.1) var stick_deadzone_enter: float = 0.5
## Minimum distance the stick need to drop bellow to be considered inactive. [br]
## Must be lower than [member stick_deadzone_enter]
@export_range(0, 1.0, 0.1) var stick_deadzone_exit: float = 0.2

@export_category("Snapping Settings")
## Number of directions the input can snap to.
@export_range(1, 32) var snap_directions: int = 8
## How close to a snapped direction the input must be before snapping. [br]
## Higher values make snapping more aggressive.
@export_range(0.0, 16.0, 0.5) var snap_tolerance: float = 8.0
## Enables direction snapping for mouse.
@export var snap_for_mouse: bool = false
## Enables direction snapping for gamepad.
@export var snap_for_gamepad: bool = false
## Enables direction snapping for touch.
@export var snap_for_touch: bool = false


## Returns [code]true[/code] when current input type is mouse and keyboard.
var is_mouse_and_keyboard_enabled: bool:
	get: return ClientState.input_type == InputType.MOUSE_KEYBOARD

## Returns [code]true[/code] when current input type is gamepad.
var is_gamepad_enabled: bool:
	get: return ClientState.input_type == InputType.GAMEPAD

## Returns [code]true[/code] when current input type is touch screen.
var is_touch_screen_enabled: bool:
	get: return ClientState.input_type == InputType.TOUCH

## Returns [code]true[/code] when mouse is active,
## the window has focus and the cursor is inside the window.
var is_mouse_onscreen: bool:
	get: return (is_mouse_and_keyboard_enabled and _mouse_in_game and _windows_focus)


static var right_touch_stick: TouchStick
static var left_touch_stick: TouchStick

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
		Input.action_press(&"player_shoot")
	else:
		Input.action_release(&"player_shoot")


func _set_input_type(type: InputType) -> void:
	if ClientState.input_type == type: return
	if type != InputType.MOUSE_KEYBOARD:
		_mouse_aiming = false
	ClientState.input_type = type


func _is_event_relevant(event: InputEvent) -> bool:
	if event is InputEventMouseMotion: return true
	if event is InputEventJoypadMotion: return true
	return event.is_pressed()


func _get_look_raw() -> Vector2:
	return Input.get_vector("player_look_left", "player_look_right", "player_look_up", "player_look_down")


func _get_move_raw() -> Vector2:
	return Input.get_vector("player_move_left", "player_move_right", "player_move_up", "player_move_down")


func _snap_direction(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO or snap_directions < 1: 
		return dir

	var angle: float = dir.angle()
	var step: float = TAU / float(snap_directions)
	var snapped_angle: float = round(angle / step) * step
	var diff: float = abs(snapped_angle - angle)

	if diff < deg_to_rad(snap_tolerance):
		return Vector2.RIGHT.rotated(snapped_angle)

	return dir


func _is_stick_aiming() -> bool:
	var length: float = _get_look_raw().length()
	var active: bool

	if length >= stick_deadzone_enter:
		active = true
	elif length <= stick_deadzone_exit:
		active = false
	return active

#endregion

#region public
## Returns global mouse position relative to world. [br]
## Returns [code]Vector2.ZERO[/code] if mouse is not active or cursor is offscreen.
func get_mouse_world_position() -> Vector2:
	if is_mouse_onscreen: 
		return get_global_mouse_position()
	return Vector2.ZERO


## Returns normalized movement direction from player input. [br]
## Returns [code]Vector2.ZERO[/code] if no directional input is detected or [member enabled] is [code]false[/code]. [br]
## [b]GAMEPAD[/b] - Left stick, via InputMap. [br]
## [b]TOUCH[/b] - Virtual joystick, via InputMap.
func get_move_direction() -> Vector2:
	if not enabled: return Vector2.ZERO
	return _get_move_raw().normalized()


## Returns normalized look direction from player input. [br]
## Caches the last valid direction, returns it when no active input is detected. [br]
## [b]MOUSE[/b] - Cursor direction relative to [member node_owner]. [br]
## [b]GAMEPAD[/b] - Right joystick direction, via InputMap. [br]
## [b]TOUCH[/b] - Right virtual joystick direction, via InputMap.
func get_look_direction() -> Vector2:
	if not enabled: return _last_look_direction

	if _is_stick_aiming(): 
		_mouse_aiming = false # Prevent using mouse direction on next getter.
		_last_look_direction = _get_look_raw().normalized()

	if _mouse_aiming and is_mouse_onscreen:
		_last_look_direction = (get_global_mouse_position() - node_owner.global_position).normalized()
	
	var use_snap: bool = (
		(_mouse_aiming and snap_for_mouse) or
		(is_gamepad_enabled and snap_for_gamepad) or
		(is_touch_screen_enabled and snap_for_touch)
	)

	return _snap_direction(_last_look_direction) if use_snap else _last_look_direction


## Returns [code]true[/code] while the attack action is held.
func is_attack_pressed() -> bool:
	if not enabled: return false
	if _mouse_aiming and not is_mouse_onscreen: return false
	return Input.is_action_pressed(&"player_shoot")


## Returns [code]true[/code] on the frame attack action was pressed.
func is_attack_just_pressed() -> bool:
	if not enabled: return false
	if _mouse_aiming and not is_mouse_onscreen: return false
	return Input.is_action_just_pressed(&"player_shoot")


## Returns [code]true[/code] on the frame attack action was released.
func is_attack_just_released() -> bool:
	if not enabled: return false
	if _mouse_aiming and not is_mouse_onscreen: return false
	return Input.is_action_just_released(&"player_shoot")


## Returns a [code]Array[/code] containing [code][bool, StringName][/code] where [code]StringName[/code] is the name of the action
## that the event is assigned to. If the key is available the [code]StringName[/code] will be empty.
static func is_event_available(event: InputEvent) -> Array:
	for action_name: StringName in get_game_actions_list():
		if InputMap.action_has_event(action_name, event):
			return [false, action_name]

	return [true, &""]


## Returns a list containing every game related input actions. Actions that start with "player_".
static func get_game_actions_list() -> Array[StringName]:
	var game_actions: Array[StringName]
	for action_name: StringName in InputMap.get_actions():
		if action_name.begins_with("player_"):
			game_actions.append(action_name)
	
	return game_actions


#endregion
