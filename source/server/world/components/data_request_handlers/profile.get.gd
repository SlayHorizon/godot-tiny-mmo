extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var target_id: int = args.get("id", 0)
	var target_player: PlayerResource
	if target_id == 0:
		# Display self profile
		target_player = instance.world_server.connected_players.get(peer_id, null)
	else:
		target_player = instance.world_server.database.player_data.players.get(target_id, null)
	if not target_player:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var from_player: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if not from_player:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var profile: Dictionary = {
		"name": target_player.display_name,
		"skin_id": target_player.skin_id,
		"stats": {
			"money": target_player.golds,
			"character_class": "???",
			"level": target_player.level
		},
		"animation": target_player.profile_animation,
		"description": target_player.profile_status,
		"self": true if target_player == from_player else false,
		"id": target_player.player_id
	}

	profile["friend"] = from_player.friends.has(target_player.player_id) and target_player != from_player;

	if target_player.active_guild:
		profile["guild_name"] = target_player.active_guild.guild_name
	profile["can_guild_invite"] = from_player.active_guild and from_player.active_guild.has_permission(from_player.player_id, Guild.Permissions.INVITE) and not from_player.active_guild.members.has(target_id)

	return profile
