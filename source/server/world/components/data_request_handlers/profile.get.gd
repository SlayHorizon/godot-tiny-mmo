extends DataRequestHandler

func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var ws: WorldServer = instance.world_server

	var from_player: PlayerResource = ws.connected_players.get(peer_id)
	if not from_player:
		return {"error": 1, "ok": false, "name": "Unknown"}

	var target_id: int = int(args.get("id", 0))
	if target_id == 0:
		target_id = from_player.player_id

	var is_self: bool = target_id == from_player.player_id

	# Step 1 get minimal profile row from DB (works for online and offline)
	var row: Dictionary = ws.database.store.get_player_profile_row(target_id)
	if row.is_empty():
		return {"error": 1, "ok": false, "name": "Unknown"}

	#Step 2: if online, overlay some fields from memory (optional)
	var target_peer_id: int = ws.player_id_to_peer_id.get(target_id, 0)
	var target_player: PlayerResource = ws.connected_players.get(target_peer_id) if target_peer_id != 0 else null
	if target_player != null:
		# Keep DB row as base, but override fields that might be more upto date in RAM
		row["display_name"] = target_player.display_name
		row["skin_id"] = target_player.skin_id
		row["level"] = target_player.level
		row["golds"] = target_player.golds
		row["profile_status"] = target_player.profile_status
		row["profile_animation"] = target_player.profile_animation
		row["active_guild_id"] = target_player.active_guild_id

	# Step 3 build final response once
	var guild_id: int = int(row.get("active_guild_id", 0))
	var guild_name: String = ws.database.store.get_guild_name(guild_id)if guild_id > 0 else ""

	var profile: Dictionary = {
		"name": str(row.get("display_name", "Unknown")),
		"skin_id": int(row.get("skin_id", 1)),
		"stats": {
			"money": int(row.get("golds", 0)),
			"character_class": "???",
			"level": int(row.get("level", 1)),
		},
		"animation": str(row.get("profile_animation", "idle")),
		"description": str(row.get("profile_status", "")),
		"self": is_self,
		"id": target_id,
		"friend": (not is_self) and from_player.friends.has(target_id),
	}

	if not guild_name.is_empty():
		profile["guild_name"] = guild_name

	#Step 4: can_guild_invite (uses inviter's active guild)
	profile["can_guild_invite"] = _can_invite(ws, from_player, target_id, is_self)

	return profile


func _can_invite(ws: WorldServer, from_player: PlayerResource, target_id: int, is_self: bool) -> bool:
	if is_self:
		return false
	if from_player.active_guild_id <= 0:
		return false

	# Load guild on demand (can add cache later)
	var g: Guild = ws.database.get_guild(from_player.active_guild_id)
	if g == null:
		return false

	if not g.has_permission(from_player.player_id, Guild.Permissions.INVITE):
		return false

	return not g.members.has(target_id)
