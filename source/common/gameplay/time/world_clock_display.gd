extends Label

func _process(delta: float) -> void:
	if multiplayer.is_server(): return

	while not InstanceClient.current:
		await get_tree().process_frame

	var world_clock: WorldClockClient = InstanceClient.current.world_client.world_clock
	var current_time: float = world_clock.get_current_time()

	var hour = int(current_time)
	var minute = int((current_time - hour) * 60)

	text = "World time: " + str(hour) + "h " + str(minute) + "m"
