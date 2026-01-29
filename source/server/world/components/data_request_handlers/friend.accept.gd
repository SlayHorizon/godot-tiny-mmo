extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var from_player: PlayerResource = world_server.connected_players.get(peer_id)
	if from_player == null:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var target_id: int = int(args.get("player_id", 0))
	if target_id <= 0:
		return {"error": 1, "ok": false, "msg": "Invalid player."}

	if target_id == from_player.player_id:
		return {"error": 1, "ok": false, "msg": "Can't add yourself."}

	var row: Dictionary = store.get_player_profile_row(target_id)
	if row.is_empty():
		return {"error": 1, "ok": false, "name": "Unknown"}

	if from_player.friends.has(target_id):
		return {"error": 1, "ok": false, "msg": "Already friend."}

	from_player.friends.append(target_id)

	# Persist now (safe + predictable)
	world_server.database.save_player(from_player)

	return {"error": 0, "ok": true, "msg": "Added friend."}
