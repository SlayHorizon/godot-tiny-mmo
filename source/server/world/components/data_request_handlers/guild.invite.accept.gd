extends DataRequestHandler
## Accepts a pending guild invite. Args: { guild_id }. Only a player on the
## guild's pending_invites list can join (the invite can't be forged). Joins at
## the default rank and adds the guild to the player's joined list.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var accepter: PlayerResource = world_server.connected_players.get(peer_id)
	if accepter == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_id: int = int(args.get("guild_id", 0))
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": ""}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if not guild.pending_invites.has(accepter.player_id):
		return {"error": 1, "ok": false, "message": "No pending invite."}
	if guild.members.has(accepter.player_id):
		guild.pending_invites.erase(accepter.player_id)
		store.save_guild(guild)
		return {"error": 1, "ok": false, "message": "Already a member."}
	if guild.members.size() >= GuildUpgrades.total_cap(guild):
		return {"error": 1, "ok": false, "message": "Guild is full."}

	store.begin()
	guild.add_member(accepter.player_id)
	guild.pending_invites.erase(accepter.player_id)
	if not accepter.joined_guild_ids.has(guild_id):
		accepter.joined_guild_ids.append(guild_id)
	# Auto-tag into the guild if the player isn't tagged anywhere yet AND there's
	# a free tag slot, so guild chat / friendly-fire / basing work immediately for
	# a first-time member. If the tag cap is full they join in the buffer (untagged).
	if accepter.active_guild_id <= 0 and _online_tagged_count(world_server, guild_id) < GuildUpgrades.tag_cap(guild):
		accepter.active_guild_id = guild_id
	store.save_guild(guild)
	store.save_player(accepter)
	store.commit()

	# May have been auto-tagged — keep the client's cached active_guild_id current.
	world_server.data_push.rpc_id(peer_id, &"active_guild_id.set", {"active_guild_id": accepter.active_guild_id})
	var pnode: Player = instance.players_by_peer_id.get(peer_id)
	if pnode != null:
		pnode.state_synchronizer.set_by_path(^":active_guild_id", accepter.active_guild_id)

	world_server.chat_service.push_system_to_player(
		instance, accepter.player_id, "Joined guild %s!" % guild.guild_name
	)

	return {"error": 0, "ok": true, "message": "Joined guild."}


## Members currently online AND tagged into [param guild_id].
func _online_tagged_count(world_server: WorldServer, guild_id: int) -> int:
	var count: int = 0
	for pid: int in world_server.connected_players:
		var other: PlayerResource = world_server.connected_players[pid]
		if other != null and other.active_guild_id == guild_id:
			count += 1
	return count
