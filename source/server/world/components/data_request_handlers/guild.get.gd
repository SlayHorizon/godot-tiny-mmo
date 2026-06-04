extends DataRequestHandler


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": ""}

	var query: String = str(args.get("q", "")).strip_edges()
	if query.is_empty():
		return {}

	var guild_id: int = store.get_guild_id_by_name(query)
	if guild_id <= 0:
		return {"error": 1, "ok": false, "message": "Not found."}

	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Not found."}

	var guild_info: Dictionary = {
		"id": guild.guild_id,
		"name": guild.guild_name,
		"size": guild.members.size(),
		"max_members": GuildUpgrades.total_cap(guild),
		"tag_cap": GuildUpgrades.tag_cap(guild),
		"logo_id": guild.logo_id,
		"leader_id": guild.leader_id,
		"leader_name": store.get_player_display_name(guild.leader_id),
		"description": guild.description,
		"motd": guild.motd,
		"seasonal_glory": guild.seasonal_glory,
		"eternal_glory": guild.eternal_glory,
		"total_kills": guild.total_kills,
		"territory_seconds": guild.territory_seconds,
		"spar_score": guild.spar_score,
		"treasury": guild.treasury,
		"hall_upgrades": _build_hall_upgrades(guild),
		"viewer_gold": Inventory.count(player.inventory, Economy.gold_id()),
		"is_active": player.active_guild_id == guild.guild_id,
	}

	if guild.members.has(player.player_id):
		guild_info["is_member"] = true
		guild_info["is_leader"] = guild.leader_id == player.player_id
		guild_info["permissions"] = guild.get_member_rank(player.player_id).get("permissions", Guild.Permissions.NONE)

	return guild_info


## Server-computed upgrade rows so the client just renders (no shared resolver
## calls on a dict). One entry per catalog upgrade with current level + next cost.
func _build_hall_upgrades(guild: Guild) -> Array:
	var out: Array = []
	for uid: StringName in GuildUpgrades.CATALOG:
		var entry: Dictionary = GuildUpgrades.CATALOG[uid]
		out.append({
			"id": String(uid),
			"name": str(entry.get("name", "?")),
			"desc": str(entry.get("desc", "")),
			"level": GuildUpgrades.level_of(guild, uid),
			"max_level": GuildUpgrades.max_level(uid),
			"next_cost": GuildUpgrades.cost_for_next(guild, uid),
		})
	return out
