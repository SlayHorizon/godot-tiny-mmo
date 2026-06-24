extends ChatCommand
## Wipe Glory + held-territory time for EVERY guild (admin maintenance). Clears the inflated numbers a
## private playtest leaves behind when guilds hold territory for days. Zeroes seasonal_glory,
## eternal_glory, total_sg_ever (the EG tracker, so Eternal Glory can't recompute back up),
## kill_counter_for_glory and territory_seconds. Leaves treasury, total_kills, members and Hall upgrades
## alone. Territory ownership is untouched too, so held flags simply start re-accruing from zero.
## Irreversible, so it requires an explicit "confirm".


func _init() -> void:
	command_name = "resetglory"
	command_priority = 100 # senior_admin (owner tier — matches /give, /gold, /grant)
	command_usage = "/resetglory confirm  (wipes Glory + base hours for ALL guilds)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2 or args[1].to_lower() != "confirm":
		return "Wipes Seasonal + Eternal Glory and held-territory time for EVERY guild (irreversible). Type: /resetglory confirm"

	var database: WorldDatabase = server_instance.world_server.database
	var count: int = 0
	for guild_id: int in database.store.get_all_guild_ids():
		var guild: Guild = database.get_guild(guild_id)
		if guild == null:
			continue
		guild.seasonal_glory = 0
		guild.eternal_glory = 0
		guild.total_sg_ever = 0
		guild.kill_counter_for_glory = 0
		guild.territory_seconds = 0
		database.save_guild(guild)
		count += 1

	ServerLog.info("Admin (peer %d) reset Glory + base hours for %d guild(s)." % [peer_id, count])
	return "Reset Glory + base hours for %d guild(s)." % count
