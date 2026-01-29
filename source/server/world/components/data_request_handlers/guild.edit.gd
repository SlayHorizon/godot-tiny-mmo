extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var guild_name: String = str(args.get("name", "")).strip_edges()
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": "Guild doesn't exist."}

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if not guild.members.has(player.player_id):
		return {"error": 1, "ok": false, "message": ""}

	var has_permission: bool = guild.has_permission(player.player_id, Guild.Permissions.EDIT)
	if not has_permission:
		return {"error": 1, "ok": false, "message": "Not allowed."}

	var description: String = str(args.get("description", ""))
	description = description.substr(0, 240)

	var logo_id: int = int(args.get("logo_id", 0))

	guild.description = description
	guild.logo_id = logo_id

	store.save_guild(guild)

	return {"error": 0, "ok": true, "message": "Saved."}
