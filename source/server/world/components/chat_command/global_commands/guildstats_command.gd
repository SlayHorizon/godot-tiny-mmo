extends ChatCommand
## DEBUG: pump the caller's ACTIVE guild's trophy counters so unlocks can be
## tested without days of play. Adds (never sets), then runs the trophy check
## immediately — unlocks announce + log exactly like the real thing.
## /guildstats kills 500       -> +500 guild kills
## /guildstats hours 30        -> +30h held-territory time
## /guildstats glory 1000      -> +1000 Seasonal Glory (Eternal follows 10:3)
## /guildstats max             -> maxes every counter (unlocks all ladders)


func _init() -> void:
	command_name = "guildstats"
	command_priority = 100 # senior_admin (owner tier — matches /give, /gold, /grant)
	command_usage = "/guildstats <kills|hours|glory> <amount>  or  /guildstats max"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var world_server: WorldServer = server_instance.world_server
	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null or player.active_guild_id <= 0:
		return "You must be tagged into a guild first."
	var guild: Guild = world_server.database.get_guild(player.active_guild_id)
	if guild == null:
		return "Guild not found."

	if args.size() < 2:
		return command_usage
	var stat: String = args[1].to_lower()
	var amount: int = int(args[2]) if args.size() > 2 else 0

	match stat:
		"kills":
			if amount <= 0:
				return command_usage
			guild.total_kills += amount
		"hours":
			if amount <= 0:
				return command_usage
			guild.territory_seconds += amount * 3600
		"glory":
			if amount <= 0:
				return command_usage
			BasingService.grant_sg(guild, amount)
		"max":
			guild.total_kills += 10000
			guild.territory_seconds += 100 * 3600
			BasingService.grant_sg(guild, 10000)
		_:
			return command_usage

	# Trophy check rides the same save, exactly like the real counter paths.
	GuildTrophies.check_and_announce(world_server, guild)
	world_server.database.save_guild(guild)

	ServerLog.info("Admin (peer %d) pumped guild stats: %s %d for guild %d." % [
		peer_id, stat, amount, guild.guild_id])
	@warning_ignore("integer_division")
	var hours: int = guild.territory_seconds / 3600
	return "%s now: %d kills, %dh base time, %d EG, %d/%d trophies." % [
		guild.guild_name, guild.total_kills, hours,
		guild.eternal_glory, guild.trophies_unlocked.size(), GuildTrophies.CATALOG.size()]
