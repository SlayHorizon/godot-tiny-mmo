extends DataRequestHandler
## Join or leave a DuelMaster's queue. Args: {master_id, action="join"|"leave"}.
## When the second player joins, the match starts immediately (SparringService
## handles the teleport + countdown + PvP-enable).


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var master_id: int = int(args.get("master_id", 0))
	var action: String = str(args.get("action", "join"))
	var team_index: int = int(args.get("team", -1))
	return SparringService.handle_queue_request(instance, peer_id, master_id, action, team_index)
