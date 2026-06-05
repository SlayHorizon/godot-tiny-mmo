extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var guild_name: String = str(args.get("name", "")).strip_edges()
	var player: PlayerResource = world_server.connected_players.get(peer_id)

	if guild_name.is_empty() or player == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}

	# Optional: enforce simple name rules early
	guild_name = guild_name.substr(0, 24)

	# Already leading a guild
	if player.led_guild_id > 0:
		return {"error": 1, "ok": false, "message": "You already have a guild."}

	# Creation costs gold — check before reserving the name.
	var gold_id: int = Economy.gold_id()
	if Inventory.count(player.inventory, gold_id) < Guild.CREATION_COST:
		return {"error": 1, "ok": false, "message": "You need %d gold to create a guild." % Guild.CREATION_COST}

	# Create + assign atomically
	store.begin()

	var new_guild_id: int = store.create_guild(guild_name, player.player_id)
	if new_guild_id <= 0:
		store.rollback()
		return {"error": 1, "ok": false, "message": "Guild name already taken."}

	var guild: Guild = store.get_guild(new_guild_id)
	if guild == null:
		store.rollback()
		return {"error": 1, "ok": false, "message": "Error while creating guild."}

	# Ensure leader is member with rank 0
	guild.members[player.player_id] = 0
	store.save_guild(guild)

	# Charge the creation cost (already verified above; persisted by save_player).
	Inventory.remove_amount_by_id(player.inventory, gold_id, Guild.CREATION_COST)

	# Update player guild fields
	player.active_guild_id = new_guild_id
	player.led_guild_id = new_guild_id

	if not player.joined_guild_ids.has(new_guild_id):
		player.joined_guild_ids.append(new_guild_id)

	store.save_player(player)

	store.commit()

	# Creator is auto-tagged into the new guild — sync the client's cached value.
	instance.world_server.data_push.rpc_id(peer_id, &"active_guild_id.set", {"active_guild_id": player.active_guild_id})
	var pnode: Player = instance.players_by_peer_id.get(peer_id)
	if pnode != null:
		pnode.state_synchronizer.set_by_path(^":active_guild_id", player.active_guild_id)

	var guild_info: Dictionary = {
		"id": guild.guild_id,
		"name": guild.guild_name,
		"size": guild.members.size(),
		"logo_id": guild.logo_id,
		"leader_id": guild.leader_id,
		"description": guild.description,
		"is_member": true,
		"permissions": guild.get_member_rank(player.player_id).get("permissions", Guild.Permissions.NONE)
	}

	instance.world_server.chat_service.push_system_to_player(
		instance,
		player.player_id,
		"Guild %s created!" % guild.guild_name
	)

	return guild_info
