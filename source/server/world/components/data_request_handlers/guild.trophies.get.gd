extends DataRequestHandler
## Trophy case data. Args: { q: guild_name }. Member-only. One entry per
## catalog trophy with unlock state + live progress, plus the current
## displayed picks and whether the viewer may edit them (EDIT permission).


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

	var entries: Array = []
	for trophy_id: StringName in GuildTrophies.CATALOG:
		var entry: Dictionary = GuildTrophies.CATALOG[trophy_id]
		var p: Vector2i = GuildTrophies.progress(guild, trophy_id)
		entries.append({
			"id": String(trophy_id),
			"name": str(entry.get("name", "?")),
			"desc": str(entry.get("desc", "")),
			"unlocked": guild.trophies_unlocked.has(trophy_id),
			"progress_text": _progress_text(entry.get("stat", &""), p),
		})

	var displayed: Array = []
	for trophy_id: StringName in guild.displayed_trophies:
		displayed.append(String(trophy_id))

	return {
		"error": 0,
		"ok": true,
		"entries": entries,
		"displayed": displayed,
		"can_edit": guild.has_permission(player.player_id, Guild.Permissions.EDIT),
	}


## Human progress readout per stat kind — raw seconds would read terribly.
func _progress_text(stat: StringName, p: Vector2i) -> String:
	match stat:
		GuildTrophies.STAT_BASE_TIME:
			@warning_ignore("integer_division")
			return "%dh / %dh" % [p.x / 3600, p.y / 3600]
		GuildTrophies.STAT_ROSTER:
			return "%d / %d members" % [p.x, p.y]
	return "%d / %d" % [p.x, p.y]
