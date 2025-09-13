extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	const MAX_RESULT: int = 10
	var i: int = 0
	var result: Dictionary
	var guild_names: PackedStringArray = instance.world_server.database.player_data.guilds.keys()
	var to_search: String = args.get("q", "")
	for guild_name: String in guild_names:
		if guild_name.to_lower().contains(to_search):
			result[guild_name] = 0
		if i >= MAX_RESULT:
			break
		i += 1
	return result
