extends DataRequestHandler
## Respawns the defender ring at a held flag for treasury funds — the
## repeatable treasury sink (guards are single-life, so an attacked base
## drains funds to restaff). Args: { flag_id }; the flag must be in the
## requester's instance (the panel is opened by clicking the flag there).
## Cost = missing guards × REINFORCE_COST_PER_GUARD. Requires membership in
## the owning guild + the EDIT permission.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}

	var flag_id: int = int(args.get("flag_id", -1))
	var flag: TerritoryFlag = null
	if instance.instance_map != null:
		flag = instance.instance_map.territory_flags.get(flag_id)
	if flag == null:
		return {"error": 1, "ok": false, "message": "No territory here."}
	if flag.owner_guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Nobody holds this territory."}
	if not flag.defenders_enabled:
		return {"error": 1, "ok": false, "message": "Defenders can't be stationed here."}

	var guild: Guild = store.get_guild(flag.owner_guild_id)
	if guild == null or not guild.members.has(player.player_id):
		return {"error": 1, "ok": false, "message": "Your guild doesn't hold this territory."}
	if not guild.has_permission(player.player_id, Guild.Permissions.EDIT):
		return {"error": 1, "ok": false, "message": "You don't have permission to spend Guild Funds."}

	var cap: int = GuildUpgrades.defender_count(guild)
	if cap <= 0:
		return {"error": 1, "ok": false, "message": "Your guild has no Defenders upgrade yet."}
	var missing: int = cap - BasingService.alive_defender_count(flag)
	if missing <= 0:
		return {"error": 1, "ok": false, "message": "All guards are still standing."}

	var cost: int = missing * GuildUpgrades.REINFORCE_COST_PER_GUARD
	if guild.treasury < cost:
		return {"error": 1, "ok": false, "message": "Not enough Guild Funds (need %d)." % cost}

	# Fail closed BEFORE charging: if the guard archetype can't resolve (e.g.
	# registry not generated yet), don't take the funds for a silent no-op.
	if ContentRegistryHub.load_by_slug(&"enemy_types", GuildUpgrades.defender_enemy_slug(guild)) == null:
		return {"error": 1, "ok": false, "message": "Guards can't be summoned right now."}

	store.begin()
	guild.treasury -= cost
	store.save_guild(guild)
	store.commit()

	# Safe to spawn directly: we're in RPC handling, not a physics callback
	# (the deferred call in _capture exists because captures fire mid-collision).
	# Belt and braces: if the spawn still produced nothing (missing container,
	# race), refund — never charge for zero guards.
	if BasingService.spawn_defenders(flag) <= 0:
		store.begin()
		guild.treasury += cost
		store.save_guild(guild)
		store.commit()
		return {"error": 1, "ok": false, "message": "Couldn't station guards here."}

	store.add_guild_log(guild.guild_id, "reinforce", player.display_name, "", {
		"territory": flag.territory_name,
		"count": missing,
		"cost": cost,
	})

	return {
		"error": 0,
		"ok": true,
		"treasury": guild.treasury,
		"defenders_alive": BasingService.alive_defender_count(flag),
		"defender_cap": cap,
	}
