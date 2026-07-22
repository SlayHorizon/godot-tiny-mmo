extends DataRequestHandler
## Sets the guild's custom banner color (WYSIWYG — tints territory banners +
## flag nameplates for everyone). Args: { q: guild_name, color: html hex }.
## EDIT permission; costs GuildUpgrades.BANNER_COLOR_COST funds PER CHANGE
## (a repeatable cosmetic sink). Held flags re-tint live.


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
		return {"error": 1, "ok": false, "message": "You don't have permission to spend Guild Funds."}

	# Preset-only: the curated list is the whole contract — no free hex entry,
	# so an invisible or obnoxious color can't be crafted client-side.
	var color_norm: String = str(args.get("color", "")).strip_edges().to_lower()
	if not GuildUpgrades.BANNER_COLORS.has(color_norm):
		return {"error": 1, "ok": false, "message": "That color isn't available."}
	if color_norm == guild.banner_color:
		return {"error": 1, "ok": false, "message": "That's already your banner color."}

	var cost: int = GuildUpgrades.BANNER_COLOR_COST
	if guild.treasury < cost:
		return {"error": 1, "ok": false, "message": "Not enough Guild Funds (need %d)." % cost}

	store.begin()
	guild.treasury -= cost
	guild.banner_color = color_norm
	store.save_guild(guild)
	store.commit()

	store.add_guild_log(guild_id, "banner", player.display_name, "", {"cost": cost})

	# Re-tint held flags live for everyone watching.
	for flag: TerritoryFlag in BasingService.held_flags(world_server, guild_id):
		flag.update_owner_banner(color_norm)

	return {"error": 0, "ok": true, "treasury": guild.treasury, "banner_color": color_norm}
