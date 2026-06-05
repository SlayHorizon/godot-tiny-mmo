extends DataRequestHandler
## Kicks a member from a guild. Args: { guild_name, target_id }. Gated by the
## KICK permission + Guild.can_act (grade hierarchy; never the leader). The
## target's player record is updated too — loaded live if online, else from the
## DB — so an offline kick doesn't leave a dangling membership.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var actor: PlayerResource = world_server.connected_players.get(peer_id)
	if actor == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("guild_name", "")).strip_edges()
	var target_id: int = int(args.get("target_id", 0))
	if guild_name.is_empty() or target_id <= 0:
		return {"error": 1, "ok": false, "message": ""}

	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if not guild.has_permission(actor.player_id, Guild.Permissions.KICK):
		return {"error": 1, "ok": false, "message": "You don't have permission to kick."}
	if not guild.can_act(actor.player_id, target_id):
		return {"error": 1, "ok": false, "message": "You can't kick this member."}

	# Resolve the target's record — the live one if they're online, else the DB.
	var target: PlayerResource = _find_online(world_server, target_id)
	if target == null:
		target = store.get_player(target_id)
	if target == null:
		return {"error": 1, "ok": false, "message": "Member not found."}

	store.begin()
	if target.active_guild_id == guild_id:
		target.active_guild_id = 0
	target.joined_guild_ids.erase(guild_id)
	guild.remove_member(target_id)
	store.save_guild(guild)
	store.save_player(target)
	store.commit()

	# If the kicked player is online, sync their client's cached active_guild_id.
	var target_peer: int = world_server.player_id_to_peer_id.get(target_id, 0)
	if target_peer > 0:
		world_server.data_push.rpc_id(target_peer, &"active_guild_id.set", {"active_guild_id": target.active_guild_id})

	return {"error": 0, "ok": true, "message": "Member kicked."}


func _find_online(world_server: WorldServer, player_id: int) -> PlayerResource:
	for pid: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[pid]
		if p != null and p.player_id == player_id:
			return p
	return null
