class_name WorldClock
extends Node


signal day_started
signal night_started
signal hour_changed(hour: int)

const HOURS_PER_DAY: float = 24.0

@export var day_speed: int = 60 ## In-game day cycle in real-time seconds.
@export var day_start_hour: int = 6
@export var night_start_hour: int = 18
@export var enabled: bool:
	set(value):
		enabled = value
		if is_inside_tree():
			set_process(value)

var is_day: bool:
	get: return check_is_day(current_hour)

var current_hour: int ## Current day cycle hour.

var _real_time_anchor: float
var _game_time_anchor: float

var _previous_hour: int
var _was_day: bool


func _ready() -> void:
	if OS.has_feature("world-server"):
		_game_time_anchor = (day_start_hour / HOURS_PER_DAY) * day_speed
		_real_time_anchor = Time.get_ticks_msec() / 1000.0
		current_hour = int(get_game_time_hour())
		_previous_hour = current_hour
		_was_day = is_day
		print(enabled)
	elif OS.has_feature("client"):
		Client.connection_changed.connect(_on_client_connected)
	set_process(enabled)


func _process(_delta: float) -> void:
	current_hour = int(get_game_time_hour())
	if current_hour != _previous_hour:
		_previous_hour = current_hour
		_handle_time_change()


func _handle_time_change() -> void:
	hour_changed.emit(current_hour)

	if is_day != _was_day:
		_was_day = is_day
		if is_day:
			day_started.emit()
		else:
			night_started.emit()


func _on_client_connected(is_connected_to_server: bool) -> void:
	if is_connected_to_server:
		Client.request_data(&"get.server_time", _on_client_time_received)
		Client.subscribe(&"get.server_time", _on_client_time_received)


func _on_client_time_received(data: Dictionary) -> void:
	if data.is_empty():
		push_warning("WorldClock client: failed to sync time with server.")
		return

	day_speed = data["day_speed"]

	var time_offset: float = 0.3

	_real_time_anchor = Time.get_ticks_msec() / 1000.0
	_game_time_anchor = data["elapsed_time"] + time_offset

	day_start_hour = data["day_start_hour"]
	night_start_hour = data["night_start_hour"]

	current_hour = int(get_game_time_hour())
	_previous_hour = current_hour
	_was_day = is_day
	enabled = data["enabled"]

## Sets the current cycle time to the provided hour. [br]
## This method also update all connected clients clock.
func server_set_current_time(hour: int) -> void:
	if not multiplayer.is_server(): return

	hour = int(clamp(hour, 0, HOURS_PER_DAY))
	_real_time_anchor = Time.get_ticks_msec() / 1000.0
	_game_time_anchor = (hour / HOURS_PER_DAY) * day_speed

	current_hour = hour
	_previous_hour = hour

	_handle_time_change()
	server_propagate_time()

## Updates all connected clients clock.
func server_propagate_time() -> void:
	if not multiplayer.is_server(): return
	var data: Dictionary = {
		"enabled": enabled,
		"day_speed": day_speed,
		"elapsed_time": get_game_time_seconds(),
		"day_start_hour": day_start_hour,
		"night_start_hour": night_start_hour,
	}
	
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"get.server_time", data)
	)

func check_is_day(hour: int = current_hour) -> bool:
	return hour >= day_start_hour and hour < night_start_hour

## Returns the in-game time in seconds based on the last real-time anchor.
func get_game_time_seconds() -> float:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var elapsed_time: float = current_time - _real_time_anchor
	return fmod(_game_time_anchor + elapsed_time, day_speed)

## Returns the in-game hours based on day cycle.
func get_game_time_hour() -> float:
	return (get_game_time_seconds() / day_speed) * HOURS_PER_DAY

## Returns normalized day progress (0.0 -> 1.0) [br]
## where 0.0 is the start of the cycle and 1.0 completes full day.
func get_day_progress() -> float:
	return get_game_time_seconds() / day_speed

## Returns formated day time. [hour:minute]
func get_formatted_time() -> String:
	var time: float = get_game_time_hour()
	var hour: int = int(time)
	var minutes: int = int((time - hour) * 60.0)
	return "%02d:%02d" % [hour, minutes]
