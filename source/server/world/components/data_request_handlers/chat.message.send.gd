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
	instance.propagate_rpc(instance.data_push.bind(&"chat.message", message))
	return {} # ACK later #{"error": 0}
