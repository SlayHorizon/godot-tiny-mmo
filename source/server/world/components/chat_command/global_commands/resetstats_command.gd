extends ChatCommand
## Admin tool to correct inflated leaderboard counters (e.g. after a boosting /
## spawn-camp exploit): zero or subtract a character's PvP kills, PvE kills, or
## arena (spar) wins. Works on an online target (edits the live resource so the
## periodic save can't clobber it) or an offline character by #id (load -> edit
## -> save). Per-character: the counters live in the character's lb_stats
## (stats_json), not the account, so an offline @account needs a #id.


## Rolling buckets every kill counter carries; reset together so the leaderboards
## (day/week/total) stay consistent.
const KILL_BUCKETS: PackedStringArray = ["_day", "_week", "_total"]


func _init() -> void:
	command_name = "resetstats"
	command_priority = 2 # admin+
	command_usage = "/resetstats <self|@account|#id> <pvp|pve|spar|all> [amount]   (no amount = zero it; otherwise subtract that many)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error

	var stat: String = args[2].to_lower()
	if stat not in ["pvp", "pve", "spar", "all"]:
		return "Unknown stat '%s'. Use pvp, pve, spar or all." % stat

	# Optional positive amount to subtract from each bucket; omitted (or <= 0) zeroes.
	var amount: int = 0
	if args.size() > 3 and args[3].is_valid_int():
		amount = maxi(0, args[3].to_int())

	# Pick the resource to edit: the LIVE one for an online target (so the change
	# sticks and the next periodic save doesn't overwrite it), else load the
	# offline character by id. An offline @account maps to no single character.
	var ws: WorldServer = server_instance.world_server
	var res: PlayerResource = null
	if target.online:
		res = target.resource
	elif target.player_id > 0:
		res = ws.database.get_player_resource(target.player_id)
	else:
		return "For an offline target, name the character by #id (try /chars <account>)."
	if res == null:
		return "Couldn't load that character."

	var parts: PackedStringArray = []
	if stat == "pvp" or stat == "all":
		parts.append("PvP=%d" % _apply(res.lb_stats, "pvp_kills", amount, KILL_BUCKETS))
	if stat == "pve" or stat == "all":
		parts.append("PvE=%d" % _apply(res.lb_stats, "pve_kills", amount, KILL_BUCKETS))
	if stat == "spar" or stat == "all":
		parts.append("ArenaWins=%d" % _apply(res.lb_stats, "arena_wins", amount, [""]))

	ws.database.save_player(res)

	var verb: String = "zeroed" if amount == 0 else "reduced by %d" % amount
	return "%s: %s (%s)." % [target.label(), verb, ", ".join(parts)]


## Zero or subtract [param amount] from each [param base]+suffix counter in
## [param stats], clamped at 0. Returns the resulting headline value (the _total
## bucket for kills, or the bare key for arena wins) for the confirmation line.
func _apply(stats: Dictionary, base: String, amount: int, suffixes: PackedStringArray) -> int:
	for suffix: String in suffixes:
		var key: String = base + suffix
		var current: int = int(stats.get(key, 0))
		stats[key] = 0 if amount == 0 else maxi(0, current - amount)
	var headline_key: String = base + ("_total" if "_total" in suffixes else "")
	return int(stats.get(headline_key, 0))
