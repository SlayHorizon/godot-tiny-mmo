extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

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
		"leader_id": guild.leader_id,
		"members": {}
	}

	for member_id: int in guild.members.keys():
		var display_name: String = store.get_player_display_name(member_id)
		if display_name.is_empty():
			display_name = str(member_id)

		guild_info["members"][display_name] = member_id

	return guild_info
