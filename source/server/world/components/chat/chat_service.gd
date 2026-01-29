class_name ChatService
extends Node

const ChatStoreSqlite := preload("res://source/server/world/components/chat/chat_store_sqlite.gd")

var store: ChatStoreSqlite

func setup_with_db(db: SQLite) -> void:
	store = ChatStoreSqlite.new(db)

func _channel_conversation_id(channel: int) -> String:
	return "global_%d" % channel

func handle_send_channel_message(instance: ServerInstance, player: PlayerResource, channel: int, text: String) -> Dictionary:
	if store == null:
		return {"error": 3, "ok": false, "message": "Chat store not initialized."}

	# Ensure conversation exists
	var convo_id := _channel_conversation_id(channel)
	store.ensure_conversation(convo_id, "global", "{}")

	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)

	# Persist
	var saved: Dictionary = store.insert_message(
		convo_id,
		now_ms,
		player.player_id,
		player.display_name,
		text
	)


	# Keep payload compatible with your current client UI
	var pushed: Dictionary = {
		"text": text,
		"channel": channel,
		"name": player.display_name,
		"id": player.player_id,

		# Optional (safe additions)
		"msg_id": saved.get("msg_id", 0),
		"time_ms": now_ms
	}

	# Broadcast like before
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"chat.message", pushed),
		instance.name
	)

	return {} # ACK later

func get_channel_history(channel: int, limit: int) -> Array:
	if store == null:
		return []

	var convo_id := _channel_conversation_id(channel)
	var rows: Array = store.fetch_last(convo_id, limit)

	# Convert DB rows -> client payload (compatible keys)
	var out: Array = []
	for r: Dictionary in rows:
		out.append({
			"text": r.get("text", ""),
			"channel": channel,
			"name": r.get("sender_name", ""),
			"id": int(r.get("sender_id", 0)),
			"msg_id": int(r.get("msg_id", 0)),
			"time_ms": int(r.get("time_ms", 0)),
		})

	return out
