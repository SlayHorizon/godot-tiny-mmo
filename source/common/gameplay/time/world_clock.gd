class_name WorldClock
extends Node

## In-game day cycle in real-time seconds.
@export var day_speed: int = 60
@export_range(0,23) var starting_hour: int = 6
@export var enabled: bool = false

var total_elapsed_time: float = 0.0

## Returns real-time seconds of the current cycle.
func get_cycle_time() -> float:
    return fmod(total_elapsed_time, day_speed)

## Returns the in-game hours of the current cycle.
func get_current_time() -> float:
    var seconds: float = get_cycle_time()
    return (seconds / day_speed) * 24.0