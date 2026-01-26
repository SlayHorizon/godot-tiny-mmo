extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var from_player: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if not from_player:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var friend_list: Dictionary
	for friend_id: int in from_player.friends:
		var friend: PlayerResource = instance.world_server.database.player_data.players.get(friend_id, null)
		if friend:
			friend_list[friend_id] = {
				"name": friend.display_name,
				"online": friend.current_peer_id > 0
			}
	return friend_list
