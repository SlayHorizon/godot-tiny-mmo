extends DataRequestHandler
## Join / leave / start / solo a DungeonMaster lobby. Args: {master_id, action}.
## "start" sends the whole queue into a private run; "solo" sends just the caller.
## DungeonService handles the group + private-instance charge.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var station: String = str(args.get("station", ""))
	var action: String = str(args.get("action", "join"))
	var hard: bool = bool(args.get("hard", false))
	return DungeonService.handle_lobby_request(instance, peer_id, station, action, hard)
