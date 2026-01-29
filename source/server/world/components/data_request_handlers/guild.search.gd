extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	const MAX_RESULT: int = 10

	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var query: String = str(args.get("q", "")).strip_edges()
	if query.is_empty():
		return {}

	var rows: Array = store.search_guilds_by_name(query, MAX_RESULT)

	var result: Dictionary = {}
	for row: Dictionary in rows:
		var name: String = str(row.get("guild_name", ""))
		if not name.is_empty():
			# result[guild_id] = guild_name
			result[name] = 0

	return result
