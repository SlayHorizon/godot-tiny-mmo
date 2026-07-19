extends DataRequestHandler
## State for the Territory panel (opened by clicking your guild's flag in the
## world). Args: { flag_id }. The flag must live in the requester's current
## instance — a click can only originate there. Returns flag state + defender
## status + what the viewer may do (reinforce gating + cost), so the panel
## renders from one round-trip.


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

	var out: Dictionary = flag.get_state_payload()
	out["error"] = 0
	out["ok"] = true
	out["defenders_enabled"] = flag.defenders_enabled

	var guild: Guild = store.get_guild(flag.owner_guild_id) if flag.owner_guild_id > 0 else null
	var cap: int = GuildUpgrades.defender_count(guild) if guild != null and flag.defenders_enabled else 0
	var alive: int = BasingService.alive_defender_count(flag)
	out["defender_cap"] = cap
	out["defenders_alive"] = alive

	# Viewer context: reinforcing needs membership in the owning guild + the
	# EDIT permission (same gate as every other treasury spend).
	var is_owner_member: bool = guild != null and guild.members.has(player.player_id)
	var missing: int = maxi(0, cap - alive)
	var cost: int = missing * GuildUpgrades.REINFORCE_COST_PER_GUARD
	out["is_owner_member"] = is_owner_member
	out["can_reinforce"] = (
		is_owner_member
		and guild.has_permission(player.player_id, Guild.Permissions.EDIT)
		and missing > 0
		and guild.treasury >= cost
	)
	out["missing"] = missing
	out["reinforce_cost"] = cost
	out["treasury"] = guild.treasury if is_owner_member else 0
	return out
