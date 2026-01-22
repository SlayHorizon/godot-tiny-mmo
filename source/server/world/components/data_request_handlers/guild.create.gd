extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var guild_name: String = args.get("name", "")
	var player_resource: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	
	if guild_name.is_empty() or not player_resource:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}

	if player_resource.led_guild:
		return {"error": 1, "ok": false, "message": "You already has a guild."}

	var guild: Guild = instance.world_server.database.player_data.create_guild(
		guild_name, player_resource.player_id
	)
	if not guild:
		return {"error": 1, "ok": false, "message": "Error while creating guild."}
	
	var guild_info: Dictionary = {
		"name": guild.guild_name,
		"size": guild.members.size(),
		"is_in_guild": true,
	}
	return guild_info
