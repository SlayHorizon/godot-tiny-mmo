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

	var members: Array = []
	for member_id: int in guild.members.keys():
		var display_name: String = store.get_player_display_name(member_id)
		if display_name.is_empty():
			display_name = str(member_id)
		var rank: Dictionary = guild.get_member_rank(member_id)
		members.append({
			"id": member_id,
			"name": display_name,
			"rank_id": int(guild.members[member_id]),
			"rank_name": str(rank.get("name", "Member")),
			"grade": int(rank.get("grade", 100)),
			"perms": int(guild.member_perms.get(member_id, 0)),
		})

	# Highest authority first (lowest grade).
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["grade"]) < int(b["grade"]))

	# Viewer info so the client can gate manage actions + populate the rank
	# dropdown without a second roundtrip.
	var viewer: Dictionary = {"player_id": 0, "grade": 100, "permissions": 0, "is_leader": false}
	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player != null and guild.members.has(player.player_id):
		var vrank: Dictionary = guild.get_member_rank(player.player_id)
		viewer = {
			"player_id": player.player_id,
			"grade": int(vrank.get("grade", 100)),
			"permissions": int(vrank.get("permissions", 0)),
			"is_leader": guild.leader_id == player.player_id,
		}

	return {
		"id": guild.guild_id,
		"name": guild.guild_name,
		"size": guild.members.size(),
		"leader_id": guild.leader_id,
		"members": members,
		"ranks": guild.ranks,
		"viewer": viewer,
	}
