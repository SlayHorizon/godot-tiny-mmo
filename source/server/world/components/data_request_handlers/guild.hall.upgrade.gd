extends DataRequestHandler

## Buys the next level of a Guild Hall upgrade with treasury (Guild Funds).
## Args: { upgrade: StringName, [id: guild_id] }. Requires the EDIT permission.
## Deducts treasury and bumps the level atomically.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}

	var upgrade_id: StringName = StringName(str(args.get("upgrade", "")))
	if not GuildUpgrades.CATALOG.has(upgrade_id):
		return {"error": 1, "ok": false, "message": "Unknown upgrade."}

	var guild_id: int = int(args.get("id", player.active_guild_id))
	if guild_id <= 0 or not player.joined_guild_ids.has(guild_id):
		return {"error": 1, "ok": false, "message": "You're not a member of that guild."}

	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	if not guild.has_permission(player.player_id, Guild.Permissions.EDIT):
		return {"error": 1, "ok": false, "message": "You don't have permission to upgrade the guild."}

	if GuildUpgrades.is_maxed(guild, upgrade_id):
		return {"error": 1, "ok": false, "message": "Already at max level."}

	var cost: int = GuildUpgrades.cost_for_next(guild, upgrade_id)
	if cost < 0:
		return {"error": 1, "ok": false, "message": "Can't upgrade that."}
	if guild.treasury < cost:
		return {"error": 1, "ok": false, "message": "Not enough Guild Funds (need %d)." % cost}

	store.begin()
	guild.treasury -= cost
	guild.upgrades[upgrade_id] = GuildUpgrades.level_of(guild, upgrade_id) + 1
	store.save_guild(guild)
	store.commit()

	return {
		"error": 0,
		"ok": true,
		"treasury": guild.treasury,
		"upgrade": String(upgrade_id),
		"level": GuildUpgrades.level_of(guild, upgrade_id),
		"cost": cost,
	}
