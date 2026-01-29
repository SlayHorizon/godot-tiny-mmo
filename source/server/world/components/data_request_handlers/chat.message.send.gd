extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if not player:
		return {"error": 1, "ok": false, "message": "Player not registred."}

	var text: String = str(args.get("text", ""))
	text = text.strip_edges()
	if text.is_empty():
		return {}

	text = text.substr(0, 120)
	var channel: int = int(args.get("channel", 0))

	var chat_service = WorldServer.curr.chat_service
	if chat_service == null:
		return {"error": 2, "ok": false, "message": "Chat service not available."}

	return chat_service.handle_send_channel_message(instance, player, channel, text)
