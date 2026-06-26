class_name BasingService
## Glory ledger for guilds: territory ticks, in-base kill milestones, and the
## 10 SG -> 3 EG conversion. All methods are static; this class holds no state.
##
## How the conversion stays drift-proof: we keep [total_sg_ever] (never reset).
## The EG target is always (total_sg_ever / 10) * 3. After every SG grant we
## compute the delta vs. the stored eternal_glory and add it once. So even if
## a future migration breaks invariants, recomputing from total_sg_ever yields
## the canonical EG.

## How often held territory pays out: each tick grants TERRITORY_TICK_SG (glory),
## treasury, and credits base-time to every owning guild per held flag. Kept at
## 5 min so progress is visible during a session (was 30 min — too coarse to feel
## like anything was happening). Glory/treasury per-tick amounts are tunable if
## the faster cadence makes the economy run hot.
const TERRITORY_TICK_SECONDS: float = 5.0 * 60.0
const TERRITORY_TICK_SG: int = 1
## PvP kills by a guilded member (anywhere — NOT territory-gated) count toward this
## milestone: every KILLS_PER_GLORY such kills grants the guild +1 SG and rolls the counter
## down. Credited from LeaderboardService.record_pvp_kill via credit_glory_kill. (Was
## "kills inside an owned territory", but a base can span multiple instances so an Area2D
## footprint can't cover it — global PvP is the working model.)
const KILLS_PER_GLORY: int = 200
## "10 SG => 3 EG" conversion ratio.
const EG_PER_10_SG: int = 3
## Ring radius (px) defender guards fan out to around a flag on capture.
const DEFENDER_SPAWN_RADIUS: float = 48.0

## In-memory accumulator of guild kills by tagged members (anywhere, not just in
## territory). Flushed to the DB on the territory tick so we don't pay a DB
## write per kill.
static var _pending_kills: Dictionary[int, int] = {}

## Dynamic prop ids of the guards currently defending each flag (flag_id ->
## [child_id, ...]), so the previous owner's guards are cleared on recapture.
static var _defenders_by_flag: Dictionary[int, Array] = {}


## Records a kill by a tagged member toward their guild's lifetime kill stat.
## Called from LeaderboardService on every PvP/PvE kill; batched (see flush).
static func record_guild_kill(guild_id: int) -> void:
	if guild_id <= 0:
		return
	_pending_kills[guild_id] = int(_pending_kills.get(guild_id, 0)) + 1


static func _flush_pending_kills(world_server: Node) -> void:
	for gid: int in _pending_kills:
		var count: int = int(_pending_kills[gid])
		if count <= 0:
			continue
		var guild: Guild = world_server.database.get_guild(gid)
		if guild != null:
			guild.total_kills += count
			world_server.database.save_guild(guild)
	_pending_kills.clear()


# --- Defenders (guild guards) ---

## Spawn the owning guild's defender guards in a ring around [param flag]. Called
## on capture (deferred — _capture runs inside a physics callback, and spawning
## an NPC's detection Area2D can't mutate physics mid-flush). Clears the previous
## owner's guards first. Guards are single-life HostileNpcs that ignore the owning
## guild. No-ops cleanly until the archetype is registered in `enemy_types`.
static func spawn_defenders(flag: TerritoryFlag) -> void:
	despawn_defenders(flag)
	if flag == null or flag.owner_guild_id <= 0:
		return
	var container: ReplicatedPropsContainer = _flag_container(flag)
	if container == null:
		return
	var guild: Guild = WorldServer.curr.database.store.get_guild(flag.owner_guild_id)
	if guild == null:
		return
	var count: int = GuildUpgrades.defender_count(guild)
	if count <= 0:
		return
	# Per-tier archetype rides the spawn as a short slug; the NPC scene is a
	# hardcoded constant (no scenes registry). Bail if the archetype isn't
	# registered yet so we never spawn a guard with no enemy_data.
	var slug: StringName = GuildUpgrades.defender_enemy_slug(guild)
	if ContentRegistryHub.load_by_slug(&"enemy_types", slug) == null:
		return
	var origin: Vector2 = container.to_local(flag.global_position)
	var ids: Array = []
	for i: int in count:
		var angle: float = TAU * float(i) / float(count)
		var spot: Vector2 = origin + Vector2(cos(angle), sin(angle)) * DEFENDER_SPAWN_RADIUS
		# owner_guild_id rides the init so clients have it too (ally bar tint);
		# applied before _ready on both sides.
		var guard: Node = container.spawn_dynamic(
			ReplicatedPropsContainer.SCENE_HOSTILE_NPC, spot,
			{"enemy_type_slug": slug, "owner_guild_id": flag.owner_guild_id}
		)
		var pid: int = container.child_id_of_node(guard)
		if pid >= 0:
			ids.append(pid)
	_defenders_by_flag[flag.flag_id] = ids


## Despawn all guards currently defending [param flag] (server + clients).
static func despawn_defenders(flag: TerritoryFlag) -> void:
	if flag == null:
		return
	var ids: Array = _defenders_by_flag.get(flag.flag_id, [])
	if not ids.is_empty():
		var container: ReplicatedPropsContainer = _flag_container(flag)
		if container != null:
			for pid: int in ids:
				container.despawn_dynamic(pid)
	_defenders_by_flag.erase(flag.flag_id)


static func _flag_container(flag: TerritoryFlag) -> ReplicatedPropsContainer:
	var map: Node = flag.get_parent()
	if map is Map:
		return (map as Map).replicated_props_container
	return null


## Grant [param amount] Seasonal Glory to [param guild] and emit any Eternal
## Glory the new total earns through the 10:3 conversion. Caller is responsible
## for persisting the Guild afterward (we batch saves where possible).
static func grant_sg(guild: Guild, amount: int) -> void:
	if guild == null or amount <= 0:
		return
	guild.seasonal_glory += amount
	guild.total_sg_ever += amount
	# Recompute EG target from scratch so we can never under- or over-grant.
	@warning_ignore("integer_division")
	var eg_target: int = (guild.total_sg_ever / 10) * EG_PER_10_SG
	if eg_target > guild.eternal_glory:
		guild.eternal_glory = eg_target


## Credit one PvP kill toward [param guild_id]'s glory milestone (global — not territory-
## gated). Every KILLS_PER_GLORY kills grants +1 SG and rolls the counter down. Called from
## LeaderboardService.record_pvp_kill for any guilded killer; a guildless kill passes
## guild_id 0 and no-ops here.
static func credit_glory_kill(guild_id: int) -> void:
	if guild_id <= 0:
		return
	var ws: WorldServer = WorldServer.curr
	if ws == null:
		return
	var guild: Guild = ws.database.get_guild(guild_id)
	if guild == null:
		return
	guild.kill_counter_for_glory += 1
	@warning_ignore("integer_division")
	var grants: int = guild.kill_counter_for_glory / KILLS_PER_GLORY
	if grants > 0:
		guild.kill_counter_for_glory -= grants * KILLS_PER_GLORY
		grant_sg(guild, grants)
		_announce_milestone(ws, guild, grants)
	ws.database.save_guild(guild)


## Iterate every charged flag across every instance and grant TERRITORY_TICK_SG
## to each owning guild per held flag. Guilds are loaded once per tick and
## saved once at the end, so DB cost is O(unique-owning-guilds) per tick — at
## the alpha scale this is essentially free.
static func tick_all_territories(world_server: Node) -> void:
	if world_server == null or world_server.instance_manager == null:
		return
	# Flush accumulated guild kills first (these guilds may not hold territory).
	_flush_pending_kills(world_server)
	var guilds_to_save: Dictionary = {} # guild_id -> Guild
	var ticks_by_guild: Dictionary = {} # guild_id -> int (for the chat announce)

	for inst_res: InstanceResource in world_server.instance_manager.instance_collection.values():
		for inst: Node in inst_res.charged_instances:
			if inst.instance_map == null:
				continue
			for flag: TerritoryFlag in inst.instance_map.territory_flags.values():
				var gid: int = flag.owner_guild_id
				if gid <= 0:
					continue
				if not guilds_to_save.has(gid):
					guilds_to_save[gid] = world_server.database.get_guild(gid)
					# Credit held-time once per tick for any guild holding ≥1 flag.
					if guilds_to_save[gid] != null:
						guilds_to_save[gid].territory_seconds += int(TERRITORY_TICK_SECONDS)
				var guild: Guild = guilds_to_save[gid]
				if guild == null:
					continue
				grant_sg(guild, TERRITORY_TICK_SG)
				guild.treasury += GuildUpgrades.treasury_per_flag(guild)
				ticks_by_guild[gid] = int(ticks_by_guild.get(gid, 0)) + TERRITORY_TICK_SG

	for gid in guilds_to_save:
		var guild: Guild = guilds_to_save[gid]
		if guild == null:
			continue
		world_server.database.save_guild(guild)
		_announce_tick(world_server, guild, int(ticks_by_guild.get(gid, 0)))


# --- internals ---

static func _announce_tick(ws: Node, guild: Guild, sg_gained: int) -> void:
	if ws.chat_service == null or sg_gained <= 0:
		return
	var msg: String = "🏛 Your guild earned %d Seasonal Glory from held territory." % sg_gained
	_push_to_guild_members(ws, guild.guild_id, msg)


static func _announce_milestone(ws: Node, guild: Guild, sg_gained: int) -> void:
	if ws.chat_service == null or sg_gained <= 0:
		return
	var kills: int = sg_gained * KILLS_PER_GLORY
	var msg: String = "🎖 %d kills in your territory earned the guild %d Seasonal Glory." % [kills, sg_gained]
	_push_to_guild_members(ws, guild.guild_id, msg)


static func _push_to_guild_members(ws: Node, guild_id: int, msg: String) -> void:
	for peer_id: int in ws.connected_players:
		var player: PlayerResource = ws.connected_players[peer_id]
		if player != null and player.active_guild_id == guild_id:
			ws.chat_service.push_system_to_player(null, player.player_id, msg)
