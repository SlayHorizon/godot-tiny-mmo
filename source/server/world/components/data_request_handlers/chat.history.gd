extends DataRequestHandler

#const ChatIds := preload("res://source/server/world/components/chat/chat_ids.gd") # if you made it
# If you don't have ChatIds, we'll inline conversation id creation.

func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if not player:
		return {"error": 1, "ok": false, "message": "Player not registred."}

	# Defaults: global channel 0 history
	var channel: int = int(args.get("channel", 0))
	var limit: int = int(args.get("limit", 50))
	limit = clampi(limit, 1, 200)

	var chat_service = instance.world_server.chat_service
	if chat_service == null:
		return {"error": 2, "ok": false, "message": "Chat service not available."}

	# Send messages as push events, so the client UI doesn't need changes.
	var messages: Array = chat_service.get_channel_history(channel, limit)
	for msg: Dictionary in messages:
		instance.world_server.data_push.rpc_id(peer_id, &"chat.message", msg)

	return {} # ACK
