extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id)
	if not player:
		return {}
	
	var joined_guilds: Array[Guild] = player.player_resource.joined_guilds
	var data: Dictionary
	for guild: Guild in joined_guilds:
		data[guild.guild_name] = guild.members.size()
	return data
