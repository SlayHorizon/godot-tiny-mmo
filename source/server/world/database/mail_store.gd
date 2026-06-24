class_name MailStore
extends RefCounted
## SQLite access for the mailbox (docs/mailbox.md). Mirrors ChatStoreSqlite: holds
## the world's SQLite handle; every query goes through query_with_bindings. `mail`
## stores content once (recipient_id = 0 = broadcast to everyone in THIS world);
## `mail_state` holds per-player read/claimed/deleted flags, created lazily so a
## broadcast is one row with independent per-player state.

## Broadcasts (recipient_id = 0, e.g. patch notes) stop showing once older than
## this — so a new character sees only recent ones, and old news auto-clears from
## every inbox. Personal mail (gifts / compensation) never expires. Tunable.
## See docs/mailbox.md.
const BROADCAST_TTL_MS: int = 10 * 24 * 60 * 60 * 1000 # 10 days

var db: SQLite


func _init(_db: SQLite) -> void:
	db = _db


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Inserts one mail and returns its new mail_id (recipient_id = 0 = broadcast).
func send(recipient_id: int, sender_name: String, subject: String, body: String, attachments_json: String) -> int:
	db.query_with_bindings(
		"INSERT INTO mail(recipient_id, sender_name, subject, body, attachments_json, created_at_ms) "
		+ "VALUES(?, ?, ?, ?, ?, ?);",
		[recipient_id, sender_name, subject, body, attachments_json, _now_ms()]
	)
	db.query("SELECT last_insert_rowid() AS id;")
	if db.query_result.is_empty():
		return -1
	return int(db.query_result[0].get("id", -1))


## All non-deleted mail visible to a player (personal + broadcasts), newest first,
## each row carrying this player's read/claimed state (NULL when never touched).
func inbox_for(player_id: int) -> Array:
	var cutoff: int = _now_ms() - BROADCAST_TTL_MS
	db.query_with_bindings(
		"SELECT m.mail_id, m.recipient_id, m.sender_name, m.subject, m.body, m.attachments_json, m.created_at_ms, "
		+ "s.read_at_ms, s.claimed_at_ms "
		+ "FROM mail m "
		+ "LEFT JOIN mail_state s ON s.mail_id = m.mail_id AND s.player_id = ? "
		+ "WHERE (m.recipient_id = ? OR (m.recipient_id = 0 AND m.created_at_ms >= ?)) AND s.deleted_at_ms IS NULL "
		+ "ORDER BY m.created_at_ms DESC;",
		[player_id, player_id, cutoff]
	)
	return db.query_result.duplicate()


## Count of unread, non-deleted mail visible to a player (for the launcher badge).
func unread_count(player_id: int) -> int:
	var cutoff: int = _now_ms() - BROADCAST_TTL_MS
	db.query_with_bindings(
		"SELECT COUNT(*) AS c FROM mail m "
		+ "LEFT JOIN mail_state s ON s.mail_id = m.mail_id AND s.player_id = ? "
		+ "WHERE (m.recipient_id = ? OR (m.recipient_id = 0 AND m.created_at_ms >= ?)) AND s.deleted_at_ms IS NULL AND s.read_at_ms IS NULL;",
		[player_id, player_id, cutoff]
	)
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("c", 0))


## Marks a mail read (first read only — preserves the original read time).
func mark_read(player_id: int, mail_id: int) -> void:
	_ensure_state(player_id, mail_id)
	db.query_with_bindings(
		"UPDATE mail_state SET read_at_ms = ? WHERE player_id = ? AND mail_id = ? AND read_at_ms IS NULL;",
		[_now_ms(), player_id, mail_id]
	)


## Soft-deletes a mail for one player (a broadcast stays for everyone else).
func soft_delete(player_id: int, mail_id: int) -> void:
	_ensure_state(player_id, mail_id)
	db.query_with_bindings(
		"UPDATE mail_state SET deleted_at_ms = ? WHERE player_id = ? AND mail_id = ?;",
		[_now_ms(), player_id, mail_id]
	)


## Resolves a mail for claiming WITHOUT mutating. Returns {"ok": bool,
## "reason"?: String, "attachments": Array}. Reasons: "missing" (not visible to
## the player / deleted), "claimed" (already), "empty" (no attachments). The
## caller grants the attachments then calls mark_claimed.
func get_claimable(player_id: int, mail_id: int) -> Dictionary:
	var cutoff: int = _now_ms() - BROADCAST_TTL_MS
	db.query_with_bindings(
		"SELECT m.attachments_json, s.claimed_at_ms, s.deleted_at_ms "
		+ "FROM mail m LEFT JOIN mail_state s ON s.mail_id = m.mail_id AND s.player_id = ? "
		+ "WHERE m.mail_id = ? AND (m.recipient_id = ? OR (m.recipient_id = 0 AND m.created_at_ms >= ?));",
		[player_id, mail_id, player_id, cutoff]
	)
	if db.query_result.is_empty():
		return {"ok": false, "reason": "missing"}
	var row: Dictionary = db.query_result[0]
	if row.get("deleted_at_ms", null) != null:
		return {"ok": false, "reason": "missing"}
	if row.get("claimed_at_ms", null) != null:
		return {"ok": false, "reason": "claimed"}
	var parsed: Variant = JSON.parse_string(str(row.get("attachments_json", "[]")))
	var attachments: Array = parsed if parsed is Array else []
	if attachments.is_empty():
		return {"ok": false, "reason": "empty"}
	return {"ok": true, "attachments": attachments}


## Marks a mail claimed for a player (idempotent — only the first claim sticks,
## which also guards a broadcast's reward to one claim per player).
func mark_claimed(player_id: int, mail_id: int) -> void:
	_ensure_state(player_id, mail_id)
	db.query_with_bindings(
		"UPDATE mail_state SET claimed_at_ms = ? WHERE player_id = ? AND mail_id = ? AND claimed_at_ms IS NULL;",
		[_now_ms(), player_id, mail_id]
	)


## Ensures a (player_id, mail_id) state row exists so per-player flags can be set.
func _ensure_state(player_id: int, mail_id: int) -> void:
	db.query_with_bindings(
		"INSERT OR IGNORE INTO mail_state(player_id, mail_id) VALUES(?, ?);",
		[player_id, mail_id]
	)
