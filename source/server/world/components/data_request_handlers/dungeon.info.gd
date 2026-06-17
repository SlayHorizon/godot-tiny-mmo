extends DataRequestHandler
## Snapshot of a DungeonMaster lobby (roster + whether the caller is queued).
## Args: {master_id}. Opened by the dungeon lobby menu.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var station: String = str(args.get("station", ""))
	return DungeonService.lobby_status(instance, peer_id, station)
