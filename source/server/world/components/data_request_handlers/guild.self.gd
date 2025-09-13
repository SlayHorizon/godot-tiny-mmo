extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id)
	if not player:
		return {}
	
	var guild: Guild = player.player_resource.guild
	var data: Dictionary
	if not guild:
		return {}
	data = {"name": guild.guild_name}
	return data
