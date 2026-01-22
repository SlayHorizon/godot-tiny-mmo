extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player_resource: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if not player_resource or not player_resource.active_guild:
		return {}
	
	player_resource.joined_guilds.erase(player_resource.active_guild)
	player_resource.active_guild.remove_member(player_resource.player_id)
	player_resource.active_guild = null
	
	return {}
