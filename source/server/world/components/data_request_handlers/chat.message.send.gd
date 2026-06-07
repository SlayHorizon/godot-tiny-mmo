extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	# Anti-spam: 5 messages per 10s per peer. Generous for normal chat, blocks
	# bot-style flooding. Tune in one place if it turns out to be too tight.
	if not RateLimiter.check(peer_id, &"chat.send", 5, 10_000):
		return {"error": 4, "ok": false, "message": "Slow down."}

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

	# Muted players can't send to any channel or DM. We push a system message
	# back so they know it's blocked (not a network bug).
	if MuteList.is_muted(player.account_name):
		chat_service.push_system_to_player(instance, player.player_id, "You are muted and cannot send messages.")
		return {"error": 3, "ok": false, "message": "muted"}

	# DM path
	var dm_target_id: int = int(args.get("dm_target_id", 0))
	if dm_target_id > 0:
		return chat_service.handle_send_dm(instance, player, dm_target_id, text)

	# Channel path
	var channel: int = int(args.get("channel", 0))
	return chat_service.handle_send_channel_message(instance, player, channel, text)
