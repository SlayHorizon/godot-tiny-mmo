extends DataRequestHandler
## Permanently dissolves a guild. Args: { guild_name, confirm }. Leader-only;
## `confirm` must EXACTLY match the guild name (the client's type-to-confirm
## dialog is re-checked server-side so a forged request can't skip it).
## Effects, in order: live flags release (guards despawn, banners go neutral),
## every member's guild references are cleared (online or offline), DB flag
## rows release, and the guild row + membership + log are deleted. Treasury
## and log die with the guild. Design locked 2026-07-19 (docs/guild.md).


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var actor: PlayerResource = world_server.connected_players.get(peer_id)
	if actor == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("guild_name", "")).strip_edges()
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": ""}
	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if guild.leader_id != actor.player_id:
		return {"error": 1, "ok": false, "message": "Only the leader can disband the guild."}
	if str(args.get("confirm", "")).strip_edges() != guild.guild_name:
		return {"error": 1, "ok": false, "message": "Confirmation doesn't match the guild name."}

	# Live flags first: guards despawn and banners go neutral for everyone
	# watching, before any row disappears.
	for flag: TerritoryFlag in BasingService.held_flags(world_server, guild_id):
		flag.release_ownership()

	var member_ids: Array = guild.members.keys()

	store.begin()
	for member_id: int in member_ids:
		var member: PlayerResource = _find_online(world_server, member_id)
		if member == null:
			member = store.get_player(member_id)
		if member == null:
			continue
		member.joined_guild_ids.erase(guild_id)
		if member.active_guild_id == guild_id:
			member.active_guild_id = 0
		if member.led_guild_id == guild_id:
			member.led_guild_id = 0
		store.save_player(member)
	store.release_guild_flags(guild_id)
	store.delete_guild(guild_id)
	store.commit()

	# Sync + notify everyone online who was a member.
	for member_id: int in member_ids:
		var member_peer: int = world_server.player_id_to_peer_id.get(member_id, 0)
		if member_peer <= 0:
			continue
		var member: PlayerResource = world_server.connected_players.get(member_peer)
		if member == null:
			continue
		world_server.data_push.rpc_id(member_peer, &"active_guild_id.set", {"active_guild_id": member.active_guild_id})
		var pnode: Player = instance.players_by_peer_id.get(member_peer)
		if pnode != null:
			pnode.state_synchronizer.set_by_path(^":active_guild_id", member.active_guild_id)
		world_server.chat_service.push_system_to_player(
			null, member_id, "Guild %s was disbanded." % guild_name
		)

	ServerLog.info("Guild '%s' (id %d) disbanded by %s; %d member(s) released." % [
		guild_name, guild_id, actor.display_name, member_ids.size()])

	return {"error": 0, "ok": true, "message": "Guild disbanded."}


func _find_online(world_server: WorldServer, player_id: int) -> PlayerResource:
	for pid: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[pid]
		if p != null and p.player_id == player_id:
			return p
	return null
