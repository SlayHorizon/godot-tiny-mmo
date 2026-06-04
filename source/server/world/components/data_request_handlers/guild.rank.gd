extends DataRequestHandler
## Changes a member's rank. Args: { guild_name, target_id, rank_id }. Gated by
## the PROMOTE permission + Guild.can_act. A non-leader can't set a member to a
## rank at or above their own authority (grade); the leader can assign any rank.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var actor: PlayerResource = world_server.connected_players.get(peer_id)
	if actor == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("guild_name", "")).strip_edges()
	var target_id: int = int(args.get("target_id", 0))
	var rank_id: int = int(args.get("rank_id", -1))
	if guild_name.is_empty() or target_id <= 0 or rank_id < 0:
		return {"error": 1, "ok": false, "message": ""}

	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if not guild.has_permission(actor.player_id, Guild.Permissions.PROMOTE):
		return {"error": 1, "ok": false, "message": "You don't have permission to change ranks."}
	if not guild.can_act(actor.player_id, target_id):
		return {"error": 1, "ok": false, "message": "You can't change this member's rank."}

	var new_rank: Dictionary = guild.get_rank(rank_id)
	if new_rank.is_empty():
		return {"error": 1, "ok": false, "message": "Invalid rank."}

	# A non-leader can't promote anyone to their own authority or higher.
	if actor.player_id != guild.leader_id:
		var actor_grade: int = int(guild.get_member_rank(actor.player_id).get("grade", 100))
		if int(new_rank.get("grade", 100)) <= actor_grade:
			return {"error": 1, "ok": false, "message": "You can't promote to your own rank or higher."}

	guild.members[target_id] = rank_id
	store.save_guild(guild)

	return {"error": 0, "ok": true, "message": "Rank updated."}
