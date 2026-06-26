extends DataRequestHandler
## Leave the current dungeon run: return the caller to the town hub and drop them
## from the group (recall_player → player_switch_instance → DungeonService
## .on_player_left dissolves the group when it empties). Args: none. The recall
## ability does the same thing from anywhere — this is the explicit, mob-proof exit
## you reach from the DungeonExit station at the entrance.


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	if WorldServer.curr == null:
		return {"ok": false, "reason": "no_server"}
	# Leave the run topped up (HP + mana), like the auto-eject on clear/fail — saves potions.
	var player: Player = instance.get_player(peer_id) as Player
	if player != null:
		player.restore_full()
	WorldServer.curr.instance_manager.recall_player(peer_id)
	return {"ok": true}
