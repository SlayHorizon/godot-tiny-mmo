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
	var equipment_json: String = JSON.stringify(player.equipment)
	var skills_json: String = JSON.stringify(player.skills)
	var mastery_json: String = JSON.stringify({
		"masteries": player.masteries,
		"loadout": player.ability_loadout,
	})
	var quests_json: String = JSON.stringify(player.quests)

	var friends_json: String = JSON.stringify(player.friends)
	var blocked_ids_json: String = JSON.stringify(player.blocked_ids)
	var owned_skins_json: String = JSON.stringify(player.owned_skins)
	var server_roles_json: String = JSON.stringify(player.server_roles)
	var stats_json: String = JSON.stringify(player.lb_stats)
	var titles_json: String = JSON.stringify({
		"unlocked": player.titles_unlocked,
		"display": player.display_title,
		"trophies": player.displayed_trophies,
	})
	var dailies_json: String = JSON.stringify({
		"quests": player.daily_quests,
		"refresh_at_ms": player.dailies_refresh_at_ms,
	})
	var dungeon_lockouts_json: String = JSON.stringify(player.dungeon_lockouts)
	var redeemed_codes_json: String = JSON.stringify(player.redeemed_codes)

	var joined_guild_ids_json: String = JSON.stringify(player.joined_guild_ids)

	db.query_with_bindings(
		"INSERT OR REPLACE INTO players("
		+ "player_id, account_name, display_name, skin_id, level, experience, available_attributes_points, "
		+ "profile_status, profile_animation, "
		+ "attributes_json, inventory_json, equipment_json, skills_json, mastery_json, quests_json, friends_json, blocked_ids_json, owned_skins_json, server_roles_json, stats_json, titles_json, dailies_json, dungeon_lockouts_json, redeemed_codes_json, "
		+ "active_guild_id, joined_guild_ids_json, led_guild_id"
		+ ") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[
			player.player_id,
			player.account_name,
			player.display_name,
			player.skin_id,
			player.level,
			player.experience,
			player.available_attributes_points,

			player.profile_status,
			player.profile_animation,

			attributes_json,
			inventory_json,
			equipment_json,
			skills_json,
			mastery_json,
			quests_json,
			friends_json,
			blocked_ids_json,
			owned_skins_json,
			server_roles_json,
			stats_json,
			titles_json,
			dailies_json,
			dungeon_lockouts_json,
			redeemed_codes_json,

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
	# The chosen creation skin is owned from the start, so it's equippable in the wardrobe.
	player.owned_skins = PackedInt64Array([player.skin_id])

	# Starting kit: ONE potion + gold, no weapon — a fresh character's first
	# decision is choosing a weapon at the starter shop (sword / bow / wand /
	# hammer, 6-8g), which seeds build identity and teaches the economy. 25g
	# covers a weapon + a potion or a cheap armor piece.
	player.inventory = {}
	Inventory.add_item(player.inventory, 1, 1) # health_potion
	Inventory.add_item(player.inventory, Economy.gold_id(), 25)
	# Starting attribute points so a new character has something to spend.
	player.available_attributes_points = PlayerResource.ATTRIBUTE_POINTS_PER_LEVEL
	# Everyone who plays the alpha carries the badge for it.
	player.titles_unlocked = PackedStringArray(["Alpha tester"])
	player.display_title = "Alpha tester"
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


## Returns the persisted ownership of a flag, or {} if no row exists (flag never
## captured — treat as unowned, full HP, no grace period).
func get_flag_state(flag_id: int) -> Dictionary:
	db.query_with_bindings(
		"SELECT flag_id, owner_guild_id, last_capture_ms FROM flags WHERE flag_id=?;",
		[flag_id]
	)
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Upsert flag ownership. Called on every capture so the territory survives a
## restart. Writes are rare (capture events) so no batching needed.
func save_flag_state(flag_id: int, owner_guild_id: int, last_capture_ms: int) -> void:
	db.query_with_bindings(
		"INSERT OR REPLACE INTO flags(flag_id, owner_guild_id, last_capture_ms) VALUES(?, ?, ?);",
		[flag_id, owner_guild_id, last_capture_ms]
	)


func get_player_profile_row(player_id: int) -> Dictionary:
	db.query_with_bindings(
		"SELECT player_id, account_name, display_name, skin_id, level, inventory_json, profile_status, profile_animation, active_guild_id, titles_json, stats_json "
		+ "FROM players WHERE player_id=?;",
		[player_id]
	)

	if db.query_result.is_empty():
		return {}

	# Flatten the title display field for the profile handler so it doesn't have
	# to parse JSON. Other fields stay in their raw form.
	var row: Dictionary = db.query_result[0]
	var titles_v: Variant = JSON.parse_string(str(row.get("titles_json", "{}")))
	if titles_v is Dictionary:
		row["display_title"] = str((titles_v as Dictionary).get("display", ""))
	return row


func _row_to_player(row: Dictionary) -> PlayerResource:
	var player: PlayerResource = PlayerResource.new()

	player.player_id = int(row.get("player_id", 0))
	player.account_name = str(row.get("account_name", ""))

	player.display_name = str(row.get("display_name", "Player"))
	player.skin_id = int(row.get("skin_id", 1))

	player.level = int(row.get("level", 1))
	player.experience = int(row.get("experience", 0))

	player.profile_status = str(row.get("profile_status", ""))
	player.profile_animation = str(row.get("profile_animation", ""))

	player.attributes.assign(JSON.parse_string(str(row.get("attributes_json", "{}"))) as Dictionary)
	player.inventory = Inventory.normalize(JSON.parse_string(str(row.get("inventory_json", "{}"))) as Dictionary)
	# Equipment: { slot_key (StringName) -> item_id (int) }; JSON gives string keys/float values.
	var equipment_raw: Dictionary = JSON.parse_string(str(row.get("equipment_json", "{}"))) as Dictionary
	player.equipment = {}
	for slot_key in equipment_raw:
		player.equipment[StringName(slot_key)] = int(equipment_raw[slot_key])
	player.available_attributes_points = int(row.get("available_attributes_points", 0))

	# Skills: { skill_name (StringName) -> {"level": int, "xp": int} }; JSON gives string
	# keys and float numbers, so normalize back to StringName keys / int values.
	var skills_raw: Dictionary = JSON.parse_string(str(row.get("skills_json", "{}"))) as Dictionary
	player.skills = {}
	for skill_name in skills_raw:
		var entry: Dictionary = skills_raw[skill_name]
		# Chosen perks: { perk_id (StringName) -> ranks (int) }.
		var perks_raw: Dictionary = entry.get("perks", {}) as Dictionary
		var perks: Dictionary = {}
		for perk_id in perks_raw:
			perks[StringName(perk_id)] = int(perks_raw[perk_id])
		player.skills[StringName(skill_name)] = {
			"level": int(entry.get("level", 1)),
			"xp": int(entry.get("xp", 0)),
			"perks": perks,
		}

	# Weapon mastery: {"masteries": {category -> {"level","xp","spent"}},
	# "loadout": {category -> node_id}}. JSON gives string keys / float values —
	# normalize like skills above (categories back to StringName, spent ids stay
	# String — that's how the runtime reads them).
	var mastery_v: Variant = JSON.parse_string(str(row.get("mastery_json", "{}")))
	player.masteries = {}
	player.ability_loadout = {}
	if mastery_v is Dictionary:
		var masteries_raw: Dictionary = (mastery_v as Dictionary).get("masteries", {})
		for category in masteries_raw:
			var m_entry: Dictionary = masteries_raw[category]
			var spent_raw: Dictionary = m_entry.get("spent", {})
			var spent: Dictionary = {}
			for node_id in spent_raw:
				spent[String(node_id)] = true
			player.masteries[StringName(category)] = {
				"level": int(m_entry.get("level", 1)),
				"xp": int(m_entry.get("xp", 0)),
				"spent": spent,
			}
		var loadout_raw: Dictionary = (mastery_v as Dictionary).get("loadout", {})
		for category in loadout_raw:
			# Array of node ids in slot order. Early saves stored a single
			# string — wrap it so alpha characters keep their pick.
			var picks_v: Variant = loadout_raw[category]
			var picks: Array = []
			if picks_v is Array:
				for pick in picks_v:
					picks.append(str(pick))
			elif not str(picks_v).is_empty():
				picks.append(str(picks_v))
			player.ability_loadout[String(category)] = picks

	# Quests: { quest_id (int) -> {"state": StringName, "progress": {obj_index(int) -> count(int)}} }.
	var quests_raw: Dictionary = JSON.parse_string(str(row.get("quests_json", "{}"))) as Dictionary
	player.quests = {}
	for quest_id in quests_raw:
		var quest_entry: Dictionary = quests_raw[quest_id]
		var progress_raw: Dictionary = quest_entry.get("progress", {}) as Dictionary
		var progress: Dictionary = {}
		for obj_index in progress_raw:
			progress[int(obj_index)] = int(progress_raw[obj_index])
		player.quests[int(quest_id)] = {
			"state": StringName(str(quest_entry.get("state", "active"))),
			"progress": progress,
		}

	var friends_v: Variant = JSON.parse_string(str(row.get("friends_json", "[]")))
	player.friends = PackedInt64Array(friends_v if friends_v is Array else [])

	var blocked_v: Variant = JSON.parse_string(str(row.get("blocked_ids_json", "[]")))
	player.blocked_ids = PackedInt64Array(blocked_v if blocked_v is Array else [])

	var owned_skins_v: Variant = JSON.parse_string(str(row.get("owned_skins_json", "[]")))
	player.owned_skins = PackedInt64Array(owned_skins_v if owned_skins_v is Array else [])
	# The equipped skin is always owned — backfills existing players (pre-wardrobe) and any
	# row whose blob drifted, so the wardrobe never shows your current look as locked.
	if not player.owned_skins.has(player.skin_id):
		player.owned_skins.append(player.skin_id)

	var redeemed_codes_v: Variant = JSON.parse_string(str(row.get("redeemed_codes_json", "[]")))
	player.redeemed_codes = PackedStringArray(redeemed_codes_v if redeemed_codes_v is Array else [])

	player.server_roles = JSON.parse_string(str(row.get("server_roles_json", "{}"))) as Dictionary

	var lb_stats_v: Variant = JSON.parse_string(str(row.get("stats_json", "{}")))
	player.lb_stats = lb_stats_v if lb_stats_v is Dictionary else {}

	var titles_v: Variant = JSON.parse_string(str(row.get("titles_json", "{}")))
	if titles_v is Dictionary:
		var unlocked_v: Variant = (titles_v as Dictionary).get("unlocked", [])
		player.titles_unlocked = PackedStringArray(unlocked_v if unlocked_v is Array else [])
		player.display_title = str((titles_v as Dictionary).get("display", ""))
		var trophies_v: Variant = (titles_v as Dictionary).get("trophies", [])
		player.displayed_trophies = PackedStringArray(trophies_v if trophies_v is Array else [])

	var dailies_v: Variant = JSON.parse_string(str(row.get("dailies_json", "{}")))
	if dailies_v is Dictionary:
		var quests_v: Variant = (dailies_v as Dictionary).get("quests", [])
		player.daily_quests = quests_v if quests_v is Array else []
		player.dailies_refresh_at_ms = int((dailies_v as Dictionary).get("refresh_at_ms", 0))

	var lockouts_v: Variant = JSON.parse_string(str(row.get("dungeon_lockouts_json", "{}")))
	player.dungeon_lockouts = lockouts_v if lockouts_v is Dictionary else {}

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


## The stable account handle for a character id (works offline). Used to map a
## player_id back to an account for account-level mute/jail.
func get_player_account_name(player_id: int) -> String:
	db.query_with_bindings(
		"SELECT account_name FROM players WHERE player_id=?;",
		[player_id]
	)

	if db.query_result.is_empty():
		return ""

	return str(db.query_result[0].get("account_name", ""))
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

		# JSON numbers parse as float, so coerce back to int ids.
		guild.pending_invites.clear()
		for pid: Variant in data.get("pending_invites", []):
			guild.pending_invites.append(int(pid))

		# JSON object keys are strings — coerce back to int player ids.
		guild.member_perms.clear()
		var perms_raw: Variant = data.get("member_perms", {})
		if perms_raw is Dictionary:
			for key: Variant in perms_raw:
				guild.member_perms[int(key)] = int(perms_raw[key])

		# Glory state — defaults to 0 for guilds that pre-dated this column.
		guild.seasonal_glory = int(data.get("seasonal_glory", 0))
		guild.eternal_glory = int(data.get("eternal_glory", 0))
		guild.total_sg_ever = int(data.get("total_sg_ever", 0))
		guild.kill_counter_for_glory = int(data.get("kill_counter_for_glory", 0))
		guild.total_kills = int(data.get("total_kills", 0))
		guild.territory_seconds = int(data.get("territory_seconds", 0))
		guild.spar_score = int(data.get("spar_score", 0))
		guild.treasury = int(data.get("treasury", 0))
		# JSON object keys are strings & values floats — coerce to StringName/int.
		var ups_raw: Variant = data.get("upgrades", {})
		if ups_raw is Dictionary:
			for key: Variant in ups_raw:
				guild.upgrades[StringName(key)] = int(ups_raw[key])

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
		"ranks": guild.ranks,
		"pending_invites": guild.pending_invites,
		"member_perms": guild.member_perms,
		"seasonal_glory": guild.seasonal_glory,
		"eternal_glory": guild.eternal_glory,
		"total_sg_ever": guild.total_sg_ever,
		"kill_counter_for_glory": guild.kill_counter_for_glory,
		"total_kills": guild.total_kills,
		"territory_seconds": guild.territory_seconds,
		"spar_score": guild.spar_score,
		"treasury": guild.treasury,
		"upgrades": guild.upgrades,
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


## Every guild id in the DB (online + offline). Added for the admin Glory-reset command; the basing
## tick only iterates flag-owning guilds, so a full enumeration was never needed before.
func get_all_guild_ids() -> Array[int]:
	db.query_with_bindings("SELECT guild_id FROM guilds;", [])
	var ids: Array[int] = []
	for row: Dictionary in db.query_result:
		ids.append(int(row.get("guild_id", 0)))
	return ids


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


## Search players by name. With [param by_account] true the query matches the
## stable account_name (@handle); otherwise it matches the character display_name.
## [param column] is a fixed internal string (not user input), so it's safe to
## interpolate. Returns rows of {player_id, account_name, display_name}.
func search_players(query: String, limit: int, by_account: bool) -> Array:
	var q: String = query.strip_edges()
	if q.is_empty():
		return []

	var like: String = "%" + q + "%"
	var column: String = "account_name" if by_account else "display_name"

	db.query_with_bindings(
		"SELECT player_id, account_name, display_name "
		+ "FROM players "
		+ "WHERE " + column + " LIKE ? COLLATE NOCASE "
		+ "ORDER BY " + column + " ASC "
		+ "LIMIT ?;",
		[like, limit]
	)

	return db.query_result

#endregion
