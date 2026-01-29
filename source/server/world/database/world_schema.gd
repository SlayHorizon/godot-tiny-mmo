extends RefCounted
class_name WorldSchema


static func ensure_schema(db: SQLite) -> void:
	_create_table_if_missing(db, "meta", {
		"key": {"data_type": "text", "primary_key": true, "not_null": true},
		"value": {"data_type": "text", "not_null": true}
	})

	var version: int = _get_schema_version(db)
	if version < 1:
		_migration_v1(db)
		_set_schema_version(db, 1)


static func _migration_v1(db: SQLite) -> void:
	_create_table_if_missing(db, "accounts", {
		"account_name": {"data_type": "text", "primary_key": true, "not_null": true}
	})

	_create_table_if_missing(db, "players", {
		"player_id": {"data_type": "int", "primary_key": true, "not_null": true},
		"account_name": {"data_type": "text", "not_null": true},
		"display_name": {"data_type": "text", "not_null": true},
		"skin_id": {"data_type": "int", "not_null": true},
		"level": {"data_type": "int", "not_null": true},
		"golds": {"data_type": "int", "not_null": true},

		"profile_status": {"data_type": "text", "not_null": true},
		"profile_animation": {"data_type": "text", "not_null": true},

		"attributes_json": {"data_type": "text", "not_null": true},
		"inventory_json": {"data_type": "text", "not_null": true},

		"friends_json": {"data_type": "text", "not_null": true},
		"server_roles_json": {"data_type": "text", "not_null": true},

		# Guild IDs (nullable for players without a guild)
		"active_guild_id": {"data_type": "int", "not_null": false},
		"joined_guild_ids_json": {"data_type": "text", "not_null": true},
		"led_guild_id": {"data_type": "int", "not_null": false}
	})

	_create_table_if_missing(db, "guilds", {
		"guild_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"guild_name": {"data_type": "text", "not_null": true},
		"leader_id": {"data_type": "int", "not_null": true},
		"data_json": {"data_type": "text", "not_null": true}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_guilds_name ON guilds(guild_name);")

	_create_table_if_missing(db, "guild_members", {
		"guild_id": {"data_type": "int", "not_null": true},
		"player_id": {"data_type": "int", "not_null": true},
		"rank": {"data_type": "int", "not_null": true}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_guild_members_pk ON guild_members(guild_id, player_id);")

	_create_table_if_missing(db, "conversations", {
		"conversation_id": {"data_type": "text", "primary_key": true, "not_null": true},
		"type": {"data_type": "text", "not_null": true}, # dm/global/guild
		"meta_json": {"data_type": "text", "not_null": true}
	})

	_create_table_if_missing(db, "messages", {
		"conversation_id": {"data_type": "text", "not_null": true},
		"msg_id": {"data_type": "int", "not_null": true},
		"time_ms": {"data_type": "int", "not_null": true},
		"sender_id": {"data_type": "int", "not_null": true},
		"sender_name": {"data_type": "text", "not_null": true},
		"text": {"data_type": "text", "not_null": true}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_pk ON messages(conversation_id, msg_id);")
	db.query("CREATE INDEX IF NOT EXISTS idx_messages_sender_time ON messages(sender_id, time_ms);")
	db.query("CREATE INDEX IF NOT EXISTS idx_messages_conv_time ON messages(conversation_id, time_ms);")


static func _create_table_if_missing(db: SQLite, table: String, dict: Dictionary) -> void:
	db.query_with_bindings(
		"SELECT name FROM sqlite_master WHERE type='table' AND name=?;",
		[table]
	)

	if db.query_result.is_empty():
		db.create_table(table, dict)


static func _get_schema_version(db: SQLite) -> int:
	db.query_with_bindings("SELECT value FROM meta WHERE key=?;", ["schema_version"])
	if db.query_result.is_empty():
		return 0

	var row: Dictionary = db.query_result[0]
	return int(row.get("value", "0"))


static func _set_schema_version(db: SQLite, v: int) -> void:
	db.query_with_bindings(
		"INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?);",
		["schema_version", str(v)]
	)
