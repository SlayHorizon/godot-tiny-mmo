extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var to_get: String = args.get("q", "")
	if to_get.is_empty():
		return {}
	var guild: Guild = instance.world_server.database.player_data.guilds.get(to_get)
	var guild_info: Dictionary
	if guild:
		guild_info = {"name": guild.guild_name, "size": guild.members.size(), "members": {}}
		for member_id: int in guild.members:
			var member: PlayerResource = instance.world_server.database.player_data.players.get(member_id)
			guild_info["members"][member.display_name] = 2
			if member_id == guild.leader_id:
				guild_info["members"][member.display_name] = 0
	return guild_info
