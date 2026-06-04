extends DataRequestHandler
## Sets a member's individual permission overrides. Args: { guild_name,
## target_id, permissions }. Only an R5 (grade 0) / the leader may grant
## individual perms. The bitmask is clamped to the grantable set and OR'd onto
## the member's rank perms by Guild.has_permission.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var actor: PlayerResource = world_server.connected_players.get(peer_id)
	if actor == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("guild_name", "")).strip_edges()
	var target_id: int = int(args.get("target_id", 0))
	var permissions: int = int(args.get("permissions", 0))
	if guild_name.is_empty() or target_id <= 0:
		return {"error": 1, "ok": false, "message": ""}

	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null or not guild.members.has(actor.player_id):
		return {"error": 1, "ok": false, "message": "You're not in this guild."}

	# Only the top tier (R5 / leader) hands out individual permissions.
	var is_r5: bool = actor.player_id == guild.leader_id or int(guild.get_member_rank(actor.player_id).get("grade", 100)) == 0
	if not is_r5:
		return {"error": 1, "ok": false, "message": "Only R5 can grant permissions."}
	if not guild.members.has(target_id):
		return {"error": 1, "ok": false, "message": "Not a member."}
	if target_id == guild.leader_id:
		return {"error": 1, "ok": false, "message": "The leader already has every permission."}

	var grantable: int = Guild.Permissions.INVITE | Guild.Permissions.KICK | Guild.Permissions.PROMOTE | Guild.Permissions.EDIT
	permissions = permissions & grantable
	if permissions == 0:
		guild.member_perms.erase(target_id)
	else:
		guild.member_perms[target_id] = permissions
	store.save_guild(guild)

	return {"error": 0, "ok": true, "message": "Permissions updated."}
