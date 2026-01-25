extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var message: Dictionary = {
		"text": args.get("text", ""),
		"channel": args.get("channel", 0),
		"name": instance.players_by_peer_id[peer_id].player_resource.display_name,
		"id": peer_id
		#"time": Time.get_
	}
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"chat.message", message),
		instance.name
	)
	return {} # ACK later #{"error": 0}
