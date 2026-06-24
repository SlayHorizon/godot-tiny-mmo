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
	if version < 2:
		_migration_v2(db)
		_set_schema_version(db, 2)
	if version < 3:
		_migration_v3(db)
		_set_schema_version(db, 3)
	if version < 4:
		_migration_v4(db)
		_set_schema_version(db, 4)
	if version < 5:
		_migration_v5(db)
		_set_schema_version(db, 5)
	if version < 6:
		_migration_v6(db)
		_set_schema_version(db, 6)
	if version < 7:
		_migration_v7(db)
		_set_schema_version(db, 7)


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
		"experience": {"data_type": "int", "not_null": true},
		"available_attributes_points": {"data_type": "int", "not_null": true},

		"profile_status": {"data_type": "text", "not_null": true},
		"profile_animation": {"data_type": "text", "not_null": true},

		"attributes_json": {"data_type": "text", "not_null": true},
		"inventory_json": {"data_type": "text", "not_null": true},
		"equipment_json": {"data_type": "text", "not_null": true},
		"skills_json": {"data_type": "text", "not_null": true},
		"quests_json": {"data_type": "text", "not_null": true},

		"friends_json": {"data_type": "text", "not_null": true},
		"server_roles_json": {"data_type": "text", "not_null": true},
		# Free-form per-player stats — currently holds leaderboard counters
		# (pvp/pve kills × day/week/total + bucket timestamps). JSON so adding
		# new metrics later is data-only, no schema migration.
		"stats_json": {"data_type": "text", "not_null": true},
		# Vanity titles: {"unlocked": ["Master Duelist", ...], "display": "..."}.
		# Persisted separately from lb_stats so titles can grow without bloating
		# the leaderboard-counter blob.
		"titles_json": {"data_type": "text", "not_null": true},
		# Daily quest board state: {"quests": [{template_id, count_so_far,
		# claimed}, ...], "refresh_at_ms": unix-ms of next UTC midnight}.
		# Reroll happens lazily on board interaction.
		"dailies_json": {"data_type": "text", "not_null": true},

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

	# Territory flags. owner_guild_id = 0 means unowned. last_capture_ms is the
	# unix timestamp (ms) of the last capture, used to enforce the post-capture
	# grace period. flag_id is a designer-assigned stable id on the placed node.
	_create_table_if_missing(db, "flags", {
		"flag_id": {"data_type": "int", "primary_key": true, "not_null": true},
		"owner_guild_id": {"data_type": "int", "not_null": true},
		"last_capture_ms": {"data_type": "int", "not_null": true}
	})

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


## v2: per-player block list. Stored as a JSON-encoded PackedInt64Array in
## the players row, mirroring how friends_json works. Idempotent so it's safe
## if a fresh DB already created the column via a future migration_v1 edit.
static func _migration_v2(db: SQLite) -> void:
	if not _column_exists(db, "players", "blocked_ids_json"):
		db.query("ALTER TABLE players ADD COLUMN blocked_ids_json TEXT NOT NULL DEFAULT '[]';")


## v3: weapon mastery. One JSON blob per player: {"masteries": {category ->
## {"level", "xp", "spent"}}, "loadout": {category -> node_id}}. See
## docs/mastery.md.
static func _migration_v3(db: SQLite) -> void:
	if not _column_exists(db, "players", "mastery_json"):
		db.query("ALTER TABLE players ADD COLUMN mastery_json TEXT NOT NULL DEFAULT '{}';")


## v4: soft dungeon lockout. One JSON blob per player: {dungeon_key -> unix-seconds
## of the last completion reward}. A re-clear inside the dungeon's window grants no
## reward (you can still run it to help). Added via ALTER — no DB wipe needed.
static func _migration_v4(db: SQLite) -> void:
	if not _column_exists(db, "players", "dungeon_lockouts_json"):
		db.query("ALTER TABLE players ADD COLUMN dungeon_lockouts_json TEXT NOT NULL DEFAULT '{}';")


## v5: owned skins for the wardrobe. JSON array of skin ids the player has purchased (the
## equipped one is players.skin_id). Added via ALTER — no DB wipe. Defaults to '[]';
## existing players backfill their current skin_id on load (see _row_to_player).
static func _migration_v5(db: SQLite) -> void:
	if not _column_exists(db, "players", "owned_skins_json"):
		db.query("ALTER TABLE players ADD COLUMN owned_skins_json TEXT NOT NULL DEFAULT '[]';")


## v6: per-character redeemed codes (see docs/redeem_codes.md). JSON array of
## upper-cased code strings the character has already claimed. Added via ALTER —
## no DB wipe. Defaults to '[]'.
static func _migration_v6(db: SQLite) -> void:
	if not _column_exists(db, "players", "redeemed_codes_json"):
		db.query("ALTER TABLE players ADD COLUMN redeemed_codes_json TEXT NOT NULL DEFAULT '[]';")


## v7: mailbox — see docs/mailbox.md. `mail` holds content once (recipient_id = 0
## means broadcast to everyone in this world); `mail_state` holds per-player
## read/claimed/deleted flags, created lazily. Two tables so a broadcast is one
## row with per-player state. Added via _create_table_if_missing — no DB wipe.
static func _migration_v7(db: SQLite) -> void:
	_create_table_if_missing(db, "mail", {
		"mail_id": {"data_type": "int", "primary_key": true, "not_null": true, "auto_increment": true},
		"recipient_id": {"data_type": "int", "not_null": true}, # 0 = broadcast to all in this world
		"sender_name": {"data_type": "text", "not_null": true},
		"subject": {"data_type": "text", "not_null": true},
		"body": {"data_type": "text", "not_null": true},
		"attachments_json": {"data_type": "text", "not_null": true},
		"created_at_ms": {"data_type": "int", "not_null": true}
	})
	db.query("CREATE INDEX IF NOT EXISTS idx_mail_recipient ON mail(recipient_id, created_at_ms DESC);")

	_create_table_if_missing(db, "mail_state", {
		"player_id": {"data_type": "int", "not_null": true},
		"mail_id": {"data_type": "int", "not_null": true},
		"read_at_ms": {"data_type": "int", "not_null": false},
		"claimed_at_ms": {"data_type": "int", "not_null": false},
		"deleted_at_ms": {"data_type": "int", "not_null": false}
	})
	db.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_mail_state_pk ON mail_state(player_id, mail_id);")


static func _column_exists(db: SQLite, table: String, column: String) -> bool:
	db.query("PRAGMA table_info(%s);" % table)
	for row: Dictionary in db.query_result:
		if str(row.get("name", "")) == column:
			return true
	return false


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
