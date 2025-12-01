class_name WorldClock
extends Node

## In-game day cycle in real-time seconds.
@export var day_speed: int = 60
@export_range(0,23) var starting_hour: int = 6
@export var enabled: bool = false

var total_elapsed_time: float = 0.0

## Returns the in-game hours of the current cycle.
func get_current_time() -> float:
    return (total_elapsed_time / day_speed) * 24.0