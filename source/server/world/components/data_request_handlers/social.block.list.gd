extends DataRequestHandler
## Returns the caller's current block list as a list of {id, name}. Client
## calls this once at bootstrap to populate ClientState.blocked_ids so chat
## filtering and the profile menu's Block/Unblock toggle have something to
## key off without a per-message round-trip.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var from_player: PlayerResource = world_server.connected_players.get(peer_id)
	if from_player == null:
		return {"error": 1, "ok": false, "entries": []}

	var entries: Array = []
	for id_v: int in from_player.blocked_ids:
		var blocked_id: int = int(id_v)
		var name: String = ""
		var row: Dictionary = store.get_player_profile_row(blocked_id)
		if not row.is_empty():
			name = str(row.get("display_name", ""))
		entries.append({"id": blocked_id, "name": name})

	return {"error": 0, "ok": true, "entries": entries}
