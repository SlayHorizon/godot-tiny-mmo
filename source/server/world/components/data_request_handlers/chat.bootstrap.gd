extends DataRequestHandler


const DEFAULT_LIMIT: int = 50
const MAX_LIMIT: int = 200


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": "Player not registered."}

	var limit: int = int(args.get("limit", DEFAULT_LIMIT))
	limit = clamp(limit, 1, MAX_LIMIT)

	var chat_service: ChatService = instance.world_server.chat_service
	if chat_service == null:
		return {"error": 3, "ok": false, "message": "Chat service not available."}

	var all: Array = []

	# World (instance/global_0)
	all.append_array(chat_service.get_channel_history(ChatConstants.CHANNEL_WORLD, limit))

	# Personal system log (sys:<player_id>)
	all.append_array(chat_service.get_system_history(player.player_id, limit))

	# Guild (guild:<guild_id>) only if player is in a guild
	var guild_id: int = int(player.active_guild_id)
	if guild_id > 0:
		all.append_array(chat_service.get_guild_history(guild_id, limit))

	# Sort by time so they appear in consistent order.
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("time_ms", 0)) < int(b.get("time_ms", 0))
	)

	for msg: Dictionary in all:
		msg["is_history"] = true
		WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", msg)

	return {"ok": true, "guild_id": guild_id}
