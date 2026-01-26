extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var guild_name: String = args.get("guild_name", "")
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": "Guild doesn't exist."}

	var player_resource: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if not player_resource:
		return {"error": 1, "ok": false, "message": ""}

	var guild: Guild = instance.world_server.database.player_data.guilds.get(guild_name)
	if not guild:
		return {"error": 1, "ok": false, "message": ""}

	if not guild.members.has(player_resource.player_id):
		return {"error": 1, "ok": false, "message": ""}

	if guild.leader_id == player_resource.player_id:
		return {"error": 1, "ok": false, "message": ""}

	if player_resource.active_guild == guild:
		player_resource.active_guild = null
	guild.remove_member(player_resource.player_id)
	player_resource.joined_guilds.erase(guild)

	return {"error": 0, "ok": true, "message": "Guild left."}
