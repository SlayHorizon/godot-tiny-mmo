class_name  WorldClockServer
extends WorldClock


func _ready() -> void:
	total_elapsed_time = (starting_hour / 24.0) * day_speed


func _process(delta: float) -> void:
	if not enabled: return
	total_elapsed_time += delta
	total_elapsed_time = fmod(total_elapsed_time, day_speed)
