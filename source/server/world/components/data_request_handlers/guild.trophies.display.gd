extends DataRequestHandler
## Sets which trophies a guild pins to its profile. Args: { q: guild_name,
## picks: Array of trophy id strings }. EDIT permission. Picks are clamped to
## unlocked-only, deduplicated, and capped at GuildTrophies.MAX_DISPLAYED.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("q", "")).strip_edges()
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": ""}
	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null or not guild.members.has(player.player_id):
		return {"error": 1, "ok": false, "message": "You're not in this guild."}
	if not guild.has_permission(player.player_id, Guild.Permissions.EDIT):
		return {"error": 1, "ok": false, "message": "You don't have permission to pick trophies."}

	var picks_raw: Variant = args.get("picks", [])
	if picks_raw is not Array:
		return {"error": 1, "ok": false, "message": ""}

	var picks: Array[StringName] = []
	for pick: Variant in (picks_raw as Array):
		var trophy_id: StringName = StringName(str(pick))
		if not guild.trophies_unlocked.has(trophy_id):
			continue
		if picks.has(trophy_id):
			continue
		picks.append(trophy_id)
		if picks.size() >= GuildTrophies.MAX_DISPLAYED:
			break

	guild.displayed_trophies = picks
	store.save_guild(guild)

	var out: Array = []
	for trophy_id: StringName in picks:
		out.append(String(trophy_id))
	return {"error": 0, "ok": true, "displayed": out}
