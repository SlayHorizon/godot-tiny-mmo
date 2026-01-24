extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var guild_name: String = args.get("name", "")
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": "Guild doesn't exist."}

	var player_resource: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if not player_resource:
		return {"error": 1, "ok": false, "message": ""}

	var guild: Guild = instance.world_server.database.player_data.guilds.get(guild_name)
	if not guild:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if not guild.members.has(player_resource.player_id):
		return {"error": 1, "ok": false, "message": ""}

	var has_permission: bool = guild.has_permission(player_resource.player_id, Guild.Permissions.EDIT)
	if not has_permission:
		return {"error": 1, "ok": false, "message": "Not allowed."}

	guild.description = args.get("description", "")
	guild.logo_id = args.get("logo_id", 0)

	return {"error": 0, "ok": true, "message": "Saved."}
