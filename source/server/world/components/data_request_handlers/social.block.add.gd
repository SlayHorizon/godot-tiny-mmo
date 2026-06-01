extends DataRequestHandler
## Adds [param id] to the caller's block list. Idempotent — adding an already
## blocked player is a no-op. Also drops the target from the friend list so
## state stays clean (you can't be friends with someone you've blocked).


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
		return {"error": 2, "ok": false, "msg": "Invalid target."}
	if target_id == from_player.player_id:
		return {"error": 3, "ok": false, "msg": "Can't block yourself."}

	# Already blocked? Treat as success so the client can blindly retry.
	if BlockList.is_blocked(from_player.player_id, target_id):
		return {"error": 0, "ok": true, "msg": "Already blocked.", "id": target_id}

	BlockList.add(from_player.player_id, target_id)

	# Mirror into the persisted PackedInt64Array so the next session keeps it.
	var ids: PackedInt64Array = from_player.blocked_ids.duplicate()
	if not ids.has(target_id):
		ids.append(target_id)
	from_player.blocked_ids = ids

	# Auto-unfriend on block — keeps the social graph consistent and avoids
	# the "blocked friend" weirdness in the UI.
	var friends: PackedInt64Array = from_player.friends.duplicate()
	var idx: int = friends.find(target_id)
	if idx >= 0:
		friends.remove_at(idx)
		from_player.friends = friends

	world_server.database.save_player(from_player)

	return {"error": 0, "ok": true, "msg": "Blocked.", "id": target_id}
