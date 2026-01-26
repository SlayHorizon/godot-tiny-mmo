extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if not player:
		return {"error": 1, "ok": false, "message": "Player not registred."}
		
	var message: Dictionary = {
		"text": args.get("text", ""),
		"channel": args.get("channel", 0),
		"name": player.display_name,
		"id": player.player_id
		#"time": Time.get_
	}
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"chat.message", message),
		instance.name
	)
	return {} # ACK later #{"error": 0}
