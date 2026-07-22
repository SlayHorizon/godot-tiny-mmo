extends DataRequestHandler
## Unlocks a guild logo/emblem with treasury funds (Guild Hall cosmetics —
## first treasury sink beyond upgrades). Args: { q: guild_name, logo_id }.
## Requires the EDIT permission. Logo 0 is free/default and never purchasable;
## equipping an owned logo goes through guild.edit.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}

	var guild_name: String = str(args.get("q", "")).strip_edges()
	if guild_name.is_empty():
		return {"error": 1, "ok": false, "message": ""}
	var guild_id: int = store.get_guild_id_by_name(guild_name)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Guild not found."}
	var guild: Guild = store.get_guild(guild_id)
	if guild == null or not guild.members.has(player.player_id):
		return {"error": 1, "ok": false, "message": "You're not in this guild."}
	if not guild.has_permission(player.player_id, Guild.Permissions.EDIT):
		return {"error": 1, "ok": false, "message": "You don't have permission to buy cosmetics."}

	var logo_id: int = int(args.get("logo_id", -1))
	if logo_id <= 0 or logo_id >= GuildLogos.count():
		return {"error": 1, "ok": false, "message": "Unknown emblem."}
	if guild.owned_logos.has(logo_id):
		return {"error": 1, "ok": false, "message": "Already owned."}

	var cost: int = GuildUpgrades.LOGO_COST
	if guild.treasury < cost:
		return {"error": 1, "ok": false, "message": "Not enough Guild Funds (need %d)." % cost}

	store.begin()
	guild.treasury -= cost
	guild.owned_logos.append(logo_id)
	store.save_guild(guild)
	store.commit()

	store.add_guild_log(guild_id, "logo", player.display_name, "", {"cost": cost})

	return {
		"error": 0,
		"ok": true,
		"treasury": guild.treasury,
		"owned_logos": Array(guild.owned_logos),
		"logo_id": logo_id,
	}
