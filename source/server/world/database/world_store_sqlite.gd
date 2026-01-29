class_name WorldStoreSqlite
extends RefCounted


var db: SQLite


func _init(_db: SQLite) -> void:
	db = _db


func begin() -> void:
	db.query("BEGIN;")


func commit() -> void:
	db.query("COMMIT;")


func rollback() -> void:
	db.query("ROLLBACK;")


#region Players
func get_player(player_id: int) -> PlayerResource:
	db.query_with_bindings("SELECT * FROM players WHERE player_id=?;", [player_id])
	if db.query_result.is_empty():
		return null

	var row: Dictionary = db.query_result[0]
	return _row_to_player(row)


func save_player(player: PlayerResource) -> void:
	var attributes_json: String = JSON.stringify(player.attributes)
	var inventory_json: String = JSON.stringify(player.inventory)

	var friends_json: String = JSON.stringify(player.friends)
	var server_roles_json: String = JSON.stringify(player.server_roles)

	var joined_guild_ids_json: String = JSON.stringify(player.joined_guild_ids)

	db.query_with_bindings(
		"INSERT OR REPLACE INTO players("
		+ "player_id, account_name, display_name, skin_id, level, golds, "
		+ "profile_status, profile_animation, "
		+ "attributes_json, inventory_json, friends_json, server_roles_json, "
		+ "active_guild_id, joined_guild_ids_json, led_guild_id"
		+ ") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[
			player.player_id,
			player.account_name,
			player.display_name,
			player.skin_id,
			player.level,
			player.golds,

			player.profile_status,
			player.profile_animation,

			attributes_json,
			inventory_json,
			friends_json,
			server_roles_json,

			player.active_guild_id,
			joined_guild_ids_json,
			player.led_guild_id
		]
	)


func create_player_character(account_name: String, character_data: Dictionary) -> int:
	db.query_with_bindings("INSERT OR IGNORE INTO accounts(account_name) VALUES(?);", [account_name])

	db.query("SELECT COALESCE(MAX(player_id), 0) AS max_id FROM players;")
	var max_id: int = int(db.query_result[0].get("max_id", 0))
	var next_id: int = max_id + 1

	var player: PlayerResource = PlayerResource.new()
	player.init(
		next_id,
		account_name,
		str(character_data.get("name", "Player")),
		int(character_data.get("skin", 1))
	)

	# Leave defaults to PlayerResource where possible.
	save_player(player)
	return next_id


func get_account_characters(account_name: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT player_id, display_name, skin_id, level FROM players WHERE account_name=?;",
		[account_name]
	)

	var out: Dictionary = {}
	for row: Dictionary in db.query_result:
		var pid: int = int(row.get("player_id", 0))
		out[pid] = {
			"name": str(row.get("display_name", "")),
			"skin": int(row.get("skin_id", 1)),
			"class": "???",
			"level": int(row.get("level", 1))
		}

	return out


func get_player_profile_row(player_id: int) -> Dictionary:
	db.query_with_bindings(
		"SELECT player_id, display_name, skin_id, level, golds, profile_status, profile_animation, active_guild_id "
		+ "FROM players WHERE player_id=?;",
		[player_id]
	)

	if db.query_result.is_empty():
		return {}

	return db.query_result[0]


func _row_to_player(row: Dictionary) -> PlayerResource:
	var player: PlayerResource = PlayerResource.new()

	player.player_id = int(row.get("player_id", 0))
	player.account_name = str(row.get("account_name", ""))

	player.display_name = str(row.get("display_name", "Player"))
	player.skin_id = int(row.get("skin_id", 1))

	player.level = int(row.get("level", 1))
	player.golds = int(row.get("golds", 0))

	player.profile_status = str(row.get("profile_status", ""))
	player.profile_animation = str(row.get("profile_animation", ""))

	player.attributes.assign(JSON.parse_string(str(row.get("attributes_json", "{}"))) as Dictionary)
	player.inventory.assign(JSON.parse_string(str(row.get("inventory_json", "{}"))) as Dictionary)

	var friends_v: Variant = JSON.parse_string(str(row.get("friends_json", "[]")))
	player.friends = PackedInt64Array(friends_v if friends_v is Array else [])

	player.server_roles = JSON.parse_string(str(row.get("server_roles_json", "{}"))) as Dictionary

	player.active_guild_id = int(row.get("active_guild_id", 0))

	var joined_v: Variant = JSON.parse_string(str(row.get("joined_guild_ids_json", "[]")))
	player.joined_guild_ids = PackedInt64Array(joined_v if joined_v is Array else [])

	player.led_guild_id = int(row.get("led_guild_id", 0))

	return player


func get_player_display_name(player_id: int) -> String:
	db.query_with_bindings(
		"SELECT display_name FROM players WHERE player_id=?;",
		[player_id]
	)

	if db.query_result.is_empty():
		return ""

	return str(db.query_result[0].get("display_name", ""))
#endregion


#region Guilds
func get_guild(guild_id: int) -> Guild:
	db.query_with_bindings("SELECT * FROM guilds WHERE guild_id=?;", [guild_id])
	if db.query_result.is_empty():
		return null

	var row: Dictionary = db.query_result[0]
	var guild: Guild = Guild.new()

	guild.guild_id = int(row.get("guild_id", 0))
	guild.guild_name = str(row.get("guild_name", ""))
	guild.leader_id = int(row.get("leader_id", 0))

	var data: Variant = JSON.parse_string(str(row.get("data_json", "{}")))
	if data is Dictionary:
		guild.motd = str(data.get("motd", ""))
		guild.description = str(data.get("description", ""))
		guild.logo_id = int(data.get("logo_id", 0))

		var ranks: Array = data.get("ranks", Guild.DEFAULT_RANKS)
		guild.ranks.assign(ranks)

	# members
	db.query_with_bindings("SELECT player_id, rank FROM guild_members WHERE guild_id=?;", [guild_id])
	guild.members = {}
	for m: Dictionary in db.query_result:
		guild.members[int(m.get("player_id", 0))] = int(m.get("rank", 0))

	return guild


func save_guild(guild: Guild) -> void:
	var data_json: String = JSON.stringify({
		"motd": guild.motd,
		"description": guild.description,
		"logo_id": guild.logo_id,
		"ranks": guild.ranks
	})

	db.query_with_bindings(
		"INSERT OR REPLACE INTO guilds(guild_id, guild_name, leader_id, data_json) VALUES(?, ?, ?, ?);",
		[guild.guild_id, guild.guild_name, guild.leader_id, data_json]
	)

	db.query_with_bindings("DELETE FROM guild_members WHERE guild_id=?;", [guild.guild_id])
	for pid in guild.members.keys():
		db.query_with_bindings(
			"INSERT INTO guild_members(guild_id, player_id, rank) VALUES(?, ?, ?);",
			[guild.guild_id, int(pid), int(guild.members[pid])]
		)


## Returns new guild_id or -1 if name exists
func create_guild(guild_name: String, leader_id: int) -> int:
	db.query_with_bindings("SELECT guild_id FROM guilds WHERE guild_name=?;", [guild_name])
	if not db.query_result.is_empty():
		return -1

	db.query_with_bindings(
		"INSERT INTO guilds(guild_name, leader_id, data_json) VALUES(?, ?, ?);",
		[guild_name, leader_id, JSON.stringify({})]
	)

	db.query("SELECT last_insert_rowid() AS id;")
	if db.query_result.is_empty():
		return -1

	return int(db.query_result[0].get("id", -1))


func get_guild_name(guild_id: int) -> String:
	if guild_id <= 0:
		return ""

	db.query_with_bindings("SELECT guild_name FROM guilds WHERE guild_id=?;", [guild_id])
	if db.query_result.is_empty():
		return ""

	return str(db.query_result[0].get("guild_name", ""))


func get_guild_id_by_name(guild_name: String) -> int:
	db.query_with_bindings(
		"SELECT guild_id FROM guilds WHERE guild_name=?;",
		[guild_name]
	)

	if db.query_result.is_empty():
		return 0

	return int(db.query_result[0].get("guild_id", 0))


func search_guilds_by_name(query: String, limit: int) -> Array:
	var q: String = query.strip_edges()
	if q.is_empty():
		return []

	var like: String = "%" + q + "%"

	db.query_with_bindings(
		"SELECT guild_id, guild_name "
		+ "FROM guilds "
		+ "WHERE guild_name LIKE ? COLLATE NOCASE "
		+ "ORDER BY guild_name ASC "
		+ "LIMIT ?;",
		[like, limit]
	)

	return db.query_result

#endregion
