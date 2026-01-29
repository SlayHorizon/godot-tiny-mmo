class_name ChatStoreSqlite
extends RefCounted

var db: SQLite

func _init(_db: SQLite) -> void:
	db = _db

func ensure_conversation(conversation_id: String, type: String, meta_json: String = "{}") -> void:
	db.query_with_bindings(
		"INSERT OR IGNORE INTO conversations(conversation_id, type, meta_json) VALUES(?, ?, ?);",
		[conversation_id, type, meta_json]
	)

func next_msg_id(conversation_id: String) -> int:
	db.query_with_bindings(
		"SELECT COALESCE(MAX(msg_id), 0) AS max_id FROM messages WHERE conversation_id=?;",
		[conversation_id]
	)
	var row: Dictionary = db.query_result[0]
	return int(row["max_id"]) + 1

func insert_message(
	conversation_id: String,
	time_ms: int,
	sender_id: int,
	sender_name: String,
	text: String
) -> Dictionary:
	var msg_id := next_msg_id(conversation_id)
	db.query_with_bindings(
		"INSERT INTO messages(conversation_id, msg_id, time_ms, sender_id, sender_name, text) "
		+ "VALUES(?, ?, ?, ?, ?, ?);",
		[conversation_id, msg_id, time_ms, sender_id, sender_name, text]
	)
	return {
		"conversation_id": conversation_id,
		"msg_id": msg_id,
		"time_ms": time_ms,
		"sender_id": sender_id,
		"sender_name": sender_name,
		"text": text
	}


func fetch_last(conversation_id: String, limit: int = 50) -> Array:
	db.query_with_bindings(
		"SELECT conversation_id, msg_id, time_ms, sender_id, sender_name, text "
		+ "FROM messages WHERE conversation_id=? "
		+ "ORDER BY msg_id DESC LIMIT ?;",
		[conversation_id, limit]
	)
	var rows: Array = db.query_result.duplicate()
	rows.reverse()
	return rows


func moderation_last_24h(sender_id: int, now_ms: int) -> Array:
	var since := now_ms - 24 * 60 * 60 * 1000
	db.query_with_bindings(
		"SELECT conversation_id, msg_id, time_ms, sender_id, text "
		+ "FROM messages WHERE sender_id=? AND time_ms>=? "
		+ "ORDER BY time_ms DESC;",
		[sender_id, since]
	)
	return db.query_result
