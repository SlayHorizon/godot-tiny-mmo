extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var guild_name: String = args.get("name", "")
	var player_resource: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	
	if guild_name.is_empty() or not player_resource:
		return {}
	
	var guild_created: bool = instance.world_server.database.player_data.create_guild(
		guild_name, player_resource.player_id
	)
	if not guild_created:
		return {}
	
	var guild: Guild = instance.world_server.database.player_data.guilds.get(guild_name)
	if not guild:
		return {}
	
	var guild_info: Dictionary = {
		"name": guild.guild_name,
		"size": guild.members.size(),
		"is_in_guild": true,
	}
	return guild_info
