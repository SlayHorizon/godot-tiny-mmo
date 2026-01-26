extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player_resource: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if not player_resource:
		return {"error": 1, "ok": false, "message": ""}
	
	var to_get: String = args.get("q", "")
	if to_get.is_empty():
		return {}
	var guild: Guild = instance.world_server.database.player_data.guilds.get(to_get)
	if not guild:
		return {"error": 1, "ok": false, "message": "Not found."}
	var guild_info: Dictionary
	guild_info = {
		"name": guild.guild_name,
		"size": guild.members.size(),
		"logo_id": guild.logo_id,
		"leader_id": guild.leader_id,
		"description": guild.description
	}
	if guild.members.has(player_resource.player_id):
		guild_info["is_member"] = true
		guild_info["permissions"] = guild.get_member_rank(player_resource.player_id).get("permissions", Guild.Permissions.NONE)
	return guild_info
