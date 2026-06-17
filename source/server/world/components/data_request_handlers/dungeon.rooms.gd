extends DataRequestHandler
## Private dungeon ROOMS (the Browse tab). Args: {master_id, action, ...}.
##   list                      → open rooms for this station
##   create {hard}             → make a room, returns its snapshot (incl. code)
##   join {room_id} | join_code {code} → join a room
##   leave / start             → leave / (leader) launch the run
## DungeonService owns the room state + the dungeon.room.update pushes.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var station: String = str(args.get("station", ""))
	var action: String = str(args.get("action", "list"))
	return DungeonService.handle_room_request(instance, peer_id, station, action, args)
