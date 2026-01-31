extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": "Player not registered."}

	var other_id: int = int(args.get("other_id", 0))
	if other_id <= 0:
		return {"error": 1, "ok": false, "message": "Invalid target."}

	var limit: int = int(args.get("limit", 50))
	limit = clamp(limit, 1, 50)

	var chat_service: ChatService = instance.world_server.chat_service
	if chat_service == null:
		return {"error": 2, "ok": false, "message": "Chat service not available."}

	var messages: Array = chat_service.get_dm_history(player.player_id, other_id, limit)

	# Push messages (same pattern as your channel history)
	for msg: Dictionary in messages:
		WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", msg)

	return {}
