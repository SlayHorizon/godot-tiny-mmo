extends DataRequestHandler
## Leave the current dungeon run: return the caller to the town hub and drop them
## from the group (recall_player → player_switch_instance → DungeonService
## .on_player_left dissolves the group when it empties). Args: none. The recall
## ability does the same thing from anywhere — this is the explicit, mob-proof exit
## you reach from the DungeonExit station at the entrance.


func data_request_handler(peer_id: int, _instance: ServerInstance, _args: Dictionary) -> Dictionary:
	if ServerHub.current == null:
		return {"ok": false, "reason": "no_server"}
	ServerHub.current.instance_manager.recall_player(peer_id)
	return {"ok": true}
