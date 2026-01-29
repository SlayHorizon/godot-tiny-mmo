extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player_resource: PlayerResource = world_server.connected_players.get(peer_id)
	if player_resource == null:
		return {}

	var out: Dictionary = {}
	for guild_id: int in player_resource.joined_guild_ids:
		var guild: Guild = store.get_guild(int(guild_id))
		if guild != null:
			out[guild.guild_name] = guild.members.size()

	return out
