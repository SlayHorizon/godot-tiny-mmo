extends DataRequestHandler
## Hands guild leadership to another member. Args: { guild_name, target_id }.
## Leader-only. The target may be OFFLINE (loaded from the DB, same as
## guild.kick) — they find out on next login. The new leader is promoted to
## rank 0 (R5); the old leader keeps their rank entry and can be re-ranked by
## the new leader. Design locked 2026-07-19 (docs/guild.md): no rank
## restriction on the recipient, no automatic/inactivity transfers.


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

	if guild.leader_id != actor.player_id:
		return {"error": 1, "ok": false, "message": "Only the leader can transfer leadership."}
	if target_id == actor.player_id:
		return {"error": 1, "ok": false, "message": "You already lead this guild."}
	if not guild.members.has(target_id):
		return {"error": 1, "ok": false, "message": "Not a member of this guild."}

	# Resolve the target's record — the live one if they're online, else the DB.
	var target: PlayerResource = _find_online(world_server, target_id)
	if target == null:
		target = store.get_player(target_id)
	if target == null:
		return {"error": 1, "ok": false, "message": "Member not found."}
	if target.led_guild_id > 0:
		return {"error": 1, "ok": false, "message": "%s already leads another guild." % target.display_name}

	store.begin()
	guild.leader_id = target_id
	guild.members[target_id] = 0
	actor.led_guild_id = 0
	target.led_guild_id = guild_id
	store.save_guild(guild)
	store.save_player(actor)
	store.save_player(target)
	store.commit()

	store.add_guild_log(guild_id, "transfer", actor.display_name, target.display_name)

	var target_peer: int = world_server.player_id_to_peer_id.get(target_id, 0)
	if target_peer > 0:
		world_server.chat_service.push_system_to_player(
			instance, target_id, "You are now the leader of %s." % guild.guild_name
		)

	return {"error": 0, "ok": true, "message": "Leadership handed to %s." % target.display_name}


func _find_online(world_server: WorldServer, player_id: int) -> PlayerResource:
	for pid: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[pid]
		if p != null and p.player_id == player_id:
			return p
	return null
