extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var target_id: int = args.get("player_id", 0)
	var target_player: PlayerResource
	target_player = instance.world_server.database.player_data.players.get(target_id, null)
	if not target_player:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var from_player: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if not from_player:
		return {"error": 1, "ok": false, "name": "Unknown"}

	if target_player == from_player:
		return {"error": 1, "ok": false, "msg": "Can't add yourself."}
	if from_player.friends.has(target_player.player_id):
		return {"error": 1, "ok": false, "msg": "Already friend."}

	from_player.friends.append(target_player.player_id)
	return {"error": 0, "ok": true, "msg": "Added friend."}
