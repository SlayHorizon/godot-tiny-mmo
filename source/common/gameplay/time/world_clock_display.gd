extends Label


func _enter_tree() -> void:
	if multiplayer.is_server():
		queue_free()


func _process(delta: float) -> void:
	var world_clock: WorldClockClient = Client.world_clock
	var current_time: float = world_clock.get_current_time()

	var hour = int(current_time)
	var minute = int((current_time - hour) * 60)

	text = "World time: " + str(hour) + "h " + str(minute) + "m"
