extends DataRequestHandler


const DEFAULT_LIMIT: int = 50
const MAX_LIMIT: int = 200


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": "Player not registered."}

	var guild_id: int = player.active_guild_id
	if guild_id <= 0:
		return {"error": 2, "ok": false, "message": "You are not in a guild."}

	var limit: int = int(args.get("limit", DEFAULT_LIMIT))
	limit = clamp(limit, 1, MAX_LIMIT)

	var chat_service: ChatService = instance.world_server.chat_service
	if chat_service == null:
		return {"error": 3, "ok": false, "message": "Chat service not available."}

	var messages: Array = chat_service.get_guild_history(guild_id, limit)
	for msg: Dictionary in messages:
		msg["is_history"] = true
		WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", msg)

	return {"ok": true, "guild_id": guild_id}
