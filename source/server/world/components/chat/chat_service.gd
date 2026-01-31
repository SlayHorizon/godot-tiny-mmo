class_name ChatService
extends Node


var store: ChatStoreSqlite


func setup_with_db(db: SQLite) -> void:
	store = ChatStoreSqlite.new(db)


func _channel_conversation_id(channel: int) -> String:
	return "global_%d" % channel


func _dm_conversation_id(a: int, b: int) -> String:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	return "dm:%d:%d" % [lo, hi]


func handle_send_channel_message(
	instance: ServerInstance,
	player: PlayerResource,
	channel: int,
	text: String
) -> Dictionary:
	if store == null:
		return {"error": 3, "ok": false, "message": "Chat store not initialized."}

	var convo_id: String = _channel_conversation_id(channel)
	store.ensure_conversation(convo_id, "global", "{}")

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)

	var saved: Dictionary = store.insert_message(
		convo_id,
		now_ms,
		player.player_id,
		player.display_name,
		text
	)

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"channel": channel,
		"name": player.display_name,
		"id": player.player_id,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms,
	}

	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"chat.message", pushed),
		instance.name
	)

	return {}


func handle_send_dm(
	instance: ServerInstance,
	sender: PlayerResource,
	other_id: int,
	text: String
) -> Dictionary:
	if store == null:
		return {"error": 3, "ok": false, "message": "Chat store not initialized."}

	if other_id <= 0 or other_id == sender.player_id:
		return {"error": 4, "ok": false, "message": "Invalid target."}

	var convo_id: String = _dm_conversation_id(sender.player_id, other_id)
	store.ensure_conversation(convo_id, "dm", "{}")

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)

	var saved: Dictionary = store.insert_message(
		convo_id,
		now_ms,
		sender.player_id,
		sender.display_name,
		text
	)

	var pushed: Dictionary = {
		"conversation_id": convo_id,
		"text": text,
		"name": sender.display_name,
		"id": sender.player_id,
		"msg_id": int(saved.get("msg_id", 0)),
		"time_ms": now_ms
	}

	# Push to sender + recipient if online
	var world_server: WorldServer = instance.world_server

	var sender_peer_id: int = int(world_server.player_id_to_peer_id.get(sender.player_id, 0))
	if sender_peer_id > 0:
		WorldServer.curr.data_push.rpc_id(sender_peer_id, &"chat.message", pushed)

	var other_peer_id: int = int(world_server.player_id_to_peer_id.get(other_id, 0))
	if other_peer_id > 0:
		WorldServer.curr.data_push.rpc_id(other_peer_id, &"chat.message", pushed)

	return {}


func get_channel_history(channel: int, limit: int) -> Array:
	if store == null:
		return []

	var convo_id: String = _channel_conversation_id(channel)
	var rows: Array = store.fetch_last(convo_id, limit)

	return _rows_to_payload(rows, convo_id, {"channel": channel})


func get_dm_history(self_id: int, other_id: int, limit: int) -> Array:
	if store == null:
		return []

	var convo_id: String = _dm_conversation_id(self_id, other_id)
	var rows: Array = store.fetch_last(convo_id, limit)

	return _rows_to_payload(rows, convo_id, {})


func _rows_to_payload(rows: Array, conversation_id: String, extra: Dictionary) -> Array:
	var out: Array = []

	for r: Dictionary in rows:
		var msg: Dictionary = {
			"conversation_id": conversation_id,
			"text": r.get("text", ""),
			"name": r.get("sender_name", ""),
			"id": int(r.get("sender_id", 0)),
			"msg_id": int(r.get("msg_id", 0)),
			"time_ms": int(r.get("time_ms", 0)),
		}

		for k: Variant in extra.keys():
			msg[k] = extra[k]

		out.append(msg)

	return out
