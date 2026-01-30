extends DataRequestHandler


func data_request_handler(
    peer_id: int,
    instance: ServerInstance,
    args: Dictionary
) -> Dictionary:
    var world_clock: WorldClock = instance.world_server.world_clock
    if not world_clock: return {}
    
    var data: Dictionary = {
        "enabled": world_clock.enabled,
        "day_speed": world_clock.day_speed,
        "elapsed_time": world_clock.get_game_time_seconds(),
        "day_start_hour": world_clock.day_start_hour,
        "night_start_hour": world_clock.night_start_hour,
    }

    return data