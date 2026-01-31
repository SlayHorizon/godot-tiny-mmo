extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": "Player not registered."}

	var text: String = str(args.get("text", "")).strip_edges()
	if text.is_empty():
		return {}

	text = text.substr(0, 120)

	var chat_service: ChatService = instance.world_server.chat_service
	if chat_service == null:
		return {"error": 2, "ok": false, "message": "Chat service not available."}

	# DM path
	var dm_target_id: int = int(args.get("dm_target_id", 0))
	if dm_target_id > 0:
		return chat_service.handle_send_dm(instance, player, dm_target_id, text)

	# Channel path
	var channel: int = int(args.get("channel", 0))
	return chat_service.handle_send_channel_message(instance, player, channel, text)
