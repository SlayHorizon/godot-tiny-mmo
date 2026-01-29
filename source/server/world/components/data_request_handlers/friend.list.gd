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

	var friend_list: Dictionary = {}

	for friend_id: int in from_player.friends:
		var name: String = store.get_player_display_name(friend_id)
		if name.is_empty():
			continue

		var online_peer_id: int = int(world_server.player_id_to_peer_id.get(friend_id, 0))

		friend_list[friend_id] = {
			"name": name,
			"online": online_peer_id > 0
		}

	return friend_list
