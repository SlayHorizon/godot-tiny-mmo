extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
    var world_clock: WorldClockServer = instance.world_server.world_clock
    if not world_clock: return {}

    var request_id: int = -1 if not args["id"] else args["id"]
    
    var data: Dictionary = {
        "server_elapsed_time": world_clock.total_elapsed_time,
        "server_day_speed": world_clock.day_speed,
        "server_time_enabled": world_clock.enabled,
        "request_id": request_id
    }

    return data