extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}

	var query: String = str(args.get("q", "")).strip_edges()
	if query.is_empty():
		return {}

	var guild_id: int = store.get_guild_id_by_name(query)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Not found."}

	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Not found."}

	var guild_info: Dictionary = {
		"id": guild.guild_id,
		"name": guild.guild_name,
		"size": guild.members.size(),
		"logo_id": guild.logo_id,
		"leader_id": guild.leader_id,
		"description": guild.description
	}

	if guild.members.has(player.player_id):
		guild_info["is_member"] = true
		guild_info["permissions"] = guild.get_member_rank(player.player_id).get("permissions", Guild.Permissions.NONE)

	return guild_info
