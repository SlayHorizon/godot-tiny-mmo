class_name LeaderboardService
## Tracks per-player rolling counters (PvP kills, PvE kills) across UTC day,
## UTC week, and lifetime buckets. Buckets roll over lazily — i.e. we check
## "is the stored bucket start still the current bucket?" on every increment.
## Players who never increment after a bucket boundary simply don't appear in
## that bucket's leaderboard until they do.
##
## Top-N queries are computed in GDScript over all player rows. At alpha scale
## (hundreds of rows) this is well under a millisecond per call; if/when the
## roster grows large enough to matter, swap in indexed columns or a cached
## ZSET-style structure.

const DAY_MS: int = 24 * 60 * 60 * 1000
const WEEK_MS: int = 7 * DAY_MS

# --- Server-side: record events ---

## Hook from HostileNpc._reward_killer. Increments PvE counters on the killer.
static func record_pve_kill(killer: Player) -> void:
	if killer == null or killer.player_resource == null:
		return
	_increment(killer.player_resource, "pve_kills")
	if killer.player_resource.active_guild_id > 0:
		BasingService.record_guild_kill(killer.player_resource.active_guild_id)


## Hook from Player.die(killer). Increments PvP counters on the killer, only
## if the killer is a Player (NPC -> player deaths aren't PvP).
static func record_pvp_kill(killer: Character) -> void:
	if killer == null or killer is not Player:
		return
	var killer_player: Player = killer
	if killer_player.player_resource == null:
		return
	_increment(killer_player.player_resource, "pvp_kills")
	if killer_player.player_resource.active_guild_id > 0:
		BasingService.record_guild_kill(killer_player.player_resource.active_guild_id)
		# Glory: a guilded member's PvP kill feeds the 200-kill SG milestone (global, not
		# territory-gated — bases can span several instances, so no Area2D can cover them).
		BasingService.credit_glory_kill(killer_player.player_resource.active_guild_id)


## Record a dungeon clear time (seconds) — keeps the player's BEST (lowest) per
## dungeon in lb_stats["dungeon_best"]. The "dungeon:<name>" board ranks these
## ASCENDING (fastest first). Data-only (lb_stats JSON), no schema change. Called
## for HARD clears only — the fixed hand-designed course is the fair race.
static func record_dungeon_clear(player: Player, dungeon_name: String, seconds: int) -> void:
	if player == null or player.player_resource == null or seconds <= 0:
		return
	var stats: Dictionary = player.player_resource.lb_stats
	var best: Dictionary = stats.get("dungeon_best", {})
	var prev: int = int(best.get(dungeon_name, 0))
	if prev == 0 or seconds < prev:
		best[dungeon_name] = seconds
		stats["dungeon_best"] = best


# --- Server-side: top-N ---

## board ids:
##   pvp_day, pvp_week, pvp_total
##   pve_day, pve_week, pve_total
##   level
##   gold            (richest — total gold held in inventory)
##   glory_seasonal, glory_eternal
##
## Returns an Array of {id, name, score, [bonus_field]} entries, ranked.
static func top_n(world_server: Node, board: String, limit: int) -> Array:
	if world_server == null or world_server.database == null:
		return []
	limit = clampi(limit, 1, 100)

	if board.begins_with("glory_"):
		return _top_n_guild(world_server, board, limit)
	if board.begins_with("dungeon:"):
		return _top_n_dungeon(world_server, board.substr(8), limit)
	return _top_n_player(world_server, board, limit)


# --- internals ---

static func _increment(player: PlayerResource, base_key: String) -> void:
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_roll_buckets(player.lb_stats, now_ms)
	player.lb_stats[base_key + "_day"] = int(player.lb_stats.get(base_key + "_day", 0)) + 1
	player.lb_stats[base_key + "_week"] = int(player.lb_stats.get(base_key + "_week", 0)) + 1
	player.lb_stats[base_key + "_total"] = int(player.lb_stats.get(base_key + "_total", 0)) + 1
	# Don't save_player here — the existing periodic save / save-on-disconnect
	# captures it. Avoiding per-kill DB writes keeps the kill path cheap.


## Reset any expired day/week counters so they start fresh at the new bucket.
## Stamps the new bucket start so we don't reset again until the next boundary.
static func _roll_buckets(stats: Dictionary, now_ms: int) -> void:
	var day_start: int = _day_start_ms(now_ms)
	if int(stats.get("lb_bucket_day_ms", 0)) != day_start:
		stats["lb_bucket_day_ms"] = day_start
		stats["pvp_kills_day"] = 0
		stats["pve_kills_day"] = 0
	var week_start: int = _week_start_ms(now_ms)
	if int(stats.get("lb_bucket_week_ms", 0)) != week_start:
		stats["lb_bucket_week_ms"] = week_start
		stats["pvp_kills_week"] = 0
		stats["pve_kills_week"] = 0


static func _day_start_ms(now_ms: int) -> int:
	# UTC day boundary.
	@warning_ignore("integer_division")
	return (now_ms / DAY_MS) * DAY_MS


static func _week_start_ms(now_ms: int) -> int:
	# UTC Monday boundary. Godot's WEEKDAY enum starts at SUNDAY=0.
	var day_start: int = _day_start_ms(now_ms)
	@warning_ignore("integer_division")
	var dow: int = Time.get_datetime_dict_from_unix_time(day_start / 1000).weekday
	var days_since_monday: int = (dow + 6) % 7
	return day_start - days_since_monday * DAY_MS


static func _top_n_player(world_server: Node, board: String, limit: int) -> Array:
	var db = world_server.database.store.db
	db.query("SELECT player_id, display_name, level, experience, stats_json, inventory_json FROM players;")
	var rows: Array = db.query_result.duplicate()
	var gold_id: int = Economy.gold_id()

	# Index online players by player_id so live counters override the (stale)
	# DB row. _increment doesn't flush to disk on every kill — saving each kill
	# would cost a DB write per arrow — so without this merge the leaderboard
	# would only reflect what was saved on the player's last disconnect.
	var live_by_player_id: Dictionary = {}
	for peer_id: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[peer_id]
		if p != null:
			live_by_player_id[p.player_id] = p

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var day_start: int = _day_start_ms(now_ms)
	var week_start: int = _week_start_ms(now_ms)

	var scored: Array = []
	for row: Dictionary in rows:
		var player_id: int = int(row.get("player_id", 0))
		var live: PlayerResource = live_by_player_id.get(player_id)

		var stats: Dictionary
		var level: int
		var display_name: String
		var experience: int
		if live != null:
			stats = live.lb_stats
			level = live.level
			display_name = live.display_name
			experience = live.experience
		else:
			var parsed: Variant = JSON.parse_string(str(row.get("stats_json", "{}")))
			stats = parsed if parsed is Dictionary else {}
			level = int(row.get("level", 1))
			display_name = str(row.get("display_name", "?"))
			experience = int(row.get("experience", 0))

		var score: int = 0
		match board:
			"pvp_day":
				if int(stats.get("lb_bucket_day_ms", 0)) == day_start:
					score = int(stats.get("pvp_kills_day", 0))
			"pvp_week":
				if int(stats.get("lb_bucket_week_ms", 0)) == week_start:
					score = int(stats.get("pvp_kills_week", 0))
			"pvp_total":
				score = int(stats.get("pvp_kills_total", 0))
			"pve_day":
				if int(stats.get("lb_bucket_day_ms", 0)) == day_start:
					score = int(stats.get("pve_kills_day", 0))
			"pve_week":
				if int(stats.get("lb_bucket_week_ms", 0)) == week_start:
					score = int(stats.get("pve_kills_week", 0))
			"pve_total":
				score = int(stats.get("pve_kills_total", 0))
			"arena_wins":
				score = int(stats.get("arena_wins", 0))
			"level":
				score = level
			"gold":
				# Richest board — total gold held. Live players use their
				# in-memory inventory; offline rows parse the saved JSON.
				var inv: Dictionary
				if live != null:
					inv = live.inventory
				else:
					var inv_parsed: Variant = JSON.parse_string(str(row.get("inventory_json", "{}")))
					inv = inv_parsed if inv_parsed is Dictionary else {}
				score = Inventory.count(inv, gold_id)
			_:
				continue
		if score <= 0 and board != "level":
			continue # Zero-score rows clutter the board.
		scored.append({
			"id": player_id,
			"name": display_name,
			"score": score,
			"sub": experience if board == "level" else 0,
		})

	# Sort: primary descending score, secondary descending sub (experience for level board).
	scored.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["sub"] > b["sub"]
	)
	return scored.slice(0, limit)


## Fastest-clear board for one dungeon. Score = best clear SECONDS, ranked
## ASCENDING (lower is better) — the inverse of the kill/level boards. Live players
## override their stale DB row, same as _top_n_player.
static func _top_n_dungeon(world_server: Node, dungeon_name: String, limit: int) -> Array:
	var db = world_server.database.store.db
	db.query("SELECT player_id, display_name, stats_json FROM players;")
	var rows: Array = db.query_result.duplicate()

	var live_by_player_id: Dictionary = {}
	for peer_id: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[peer_id]
		if p != null:
			live_by_player_id[p.player_id] = p

	var scored: Array = []
	for row: Dictionary in rows:
		var player_id: int = int(row.get("player_id", 0))
		var live: PlayerResource = live_by_player_id.get(player_id)
		var stats: Dictionary
		var display_name: String
		if live != null:
			stats = live.lb_stats
			display_name = live.display_name
		else:
			var parsed: Variant = JSON.parse_string(str(row.get("stats_json", "{}")))
			stats = parsed if parsed is Dictionary else {}
			display_name = str(row.get("display_name", "?"))
		var best: Variant = stats.get("dungeon_best", {})
		if best is not Dictionary:
			continue
		var seconds: int = int((best as Dictionary).get(dungeon_name, 0))
		if seconds <= 0:
			continue
		scored.append({"id": player_id, "name": display_name, "score": seconds, "sub": 0})
	scored.sort_custom(func(a, b): return a["score"] < b["score"]) # fastest first
	return scored.slice(0, limit)


static func _top_n_guild(world_server: Node, board: String, limit: int) -> Array:
	var db = world_server.database.store.db
	db.query("SELECT guild_id, guild_name, data_json FROM guilds;")
	var rows: Array = db.query_result.duplicate()

	var scored: Array = []
	for row: Dictionary in rows:
		var data: Variant = JSON.parse_string(str(row.get("data_json", "{}")))
		if data is not Dictionary:
			continue
		var score: int = 0
		match board:
			"glory_seasonal":
				score = int(data.get("seasonal_glory", 0))
			"glory_eternal":
				score = int(data.get("eternal_glory", 0))
			_:
				continue
		if score <= 0:
			continue
		scored.append({
			"id": int(row.get("guild_id", 0)),
			"name": str(row.get("guild_name", "?")),
			"score": score,
			"sub": 0,
		})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	return scored.slice(0, limit)
