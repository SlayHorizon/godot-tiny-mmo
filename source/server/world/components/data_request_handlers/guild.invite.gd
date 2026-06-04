extends DataRequestHandler
## Invites a player into the inviter's active guild. Args: { id: target_id }.
## Gated by the INVITE permission. Records a pending invite on the guild and
## pushes a "guild.invite" notification to the target (the same mechanism as
## friend requests). The target joins via guild.invite.accept.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var actor: PlayerResource = world_server.connected_players.get(peer_id)
	if actor == null:
		return {"error": 1, "ok": false, "message": ""}

	var target_id: int = int(args.get("id", 0))
	if target_id <= 0 or target_id == actor.player_id:
		return {"error": 1, "ok": false, "message": ""}

	# You invite into the guild you're tagged into.
	var guild_id: int = actor.active_guild_id
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Tag into a guild first."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if not guild.has_permission(actor.player_id, Guild.Permissions.INVITE):
		return {"error": 1, "ok": false, "message": "You don't have permission to invite."}
	if guild.members.has(target_id):
		return {"error": 1, "ok": false, "message": "Already a member."}
	if guild.members.size() >= Guild.MAX_MEMBERS:
		return {"error": 1, "ok": false, "message": "Guild is full."}
	if store.get_player_profile_row(target_id).is_empty():
		return {"error": 1, "ok": false, "message": "Player not found."}

	if not guild.pending_invites.has(target_id):
		guild.pending_invites.append(target_id)
		store.save_guild(guild)

	var target_peer_id: int = int(world_server.player_id_to_peer_id.get(target_id, 0))
	if target_peer_id > 0:
		world_server.data_push.rpc_id(
			target_peer_id,
			&"notification",
			{
				"topic": "guild.invite",
				"guild_name": guild.guild_name,
				"guild_id": guild.guild_id,
				"from_name": actor.display_name,
			}
		)

	return {"error": 0, "ok": true, "message": "Invite sent."}
