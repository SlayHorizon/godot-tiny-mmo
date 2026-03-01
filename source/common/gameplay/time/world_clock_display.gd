extends Label
## Note: this is only for debugging

func _enter_tree() -> void:
    if multiplayer.is_server():
        queue_free()


func _process(delta: float) -> void:
    var world_clock: WorldClock = Client.world_clock
    if not world_clock.enabled: return
    text = "World clock: " + world_clock.get_formatted_time()