extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player_resource: PlayerResource = world_server.connected_players.get(peer_id)
	if player_resource == null:
		return {}

	var guilds: Array = []
	for guild_id: int in player_resource.joined_guild_ids:
		var guild: Guild = store.get_guild(int(guild_id))
		if guild != null:
			guilds.append({
				"id": guild.guild_id,
				"name": guild.guild_name,
				"size": guild.members.size(),
				"logo_id": guild.logo_id,
				"is_active": player_resource.active_guild_id == guild.guild_id,
			})

	return {"guilds": guilds}
