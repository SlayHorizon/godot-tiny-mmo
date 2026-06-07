extends DataRequestHandler
## Removes [param id] from the caller's friend list. No-op (still "ok") if the
## target wasn't a friend, so the client can call it idempotently.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server

	var from_player: PlayerResource = world_server.connected_players.get(peer_id)
	if from_player == null:
		return {"error": 1, "ok": false, "msg": "Not connected."}

	var target_id: int = int(args.get("id", 0))
	if target_id <= 0:
		return {"error": 1, "ok": false, "msg": "Invalid player."}

	var friends: PackedInt64Array = from_player.friends.duplicate()
	var idx: int = friends.find(target_id)
	if idx < 0:
		return {"error": 0, "ok": true, "msg": "Not a friend."}

	friends.remove_at(idx)
	from_player.friends = friends
	world_server.database.save_player(from_player)

	return {"error": 0, "ok": true, "msg": "Removed friend."}
