class_name BasingService
## Glory ledger for guilds: territory ticks, in-base kill milestones, and the
## 10 SG -> 3 EG conversion. All methods are static; this class holds no state.
##
## How the conversion stays drift-proof: we keep [total_sg_ever] (never reset).
## The EG target is always (total_sg_ever / 10) * 3. After every SG grant we
## compute the delta vs. the stored eternal_glory and add it once. So even if
## a future migration breaks invariants, recomputing from total_sg_ever yields
## the canonical EG.

## How long a guild must hold a territory before earning the next tick. Each
## tick grants TERRITORY_TICK_SG to every owning guild for every held flag.
const TERRITORY_TICK_SECONDS: float = 30.0 * 60.0
const TERRITORY_TICK_SG: int = 1
## Kills made inside an owned territory by a member of the owning guild count
## toward this milestone. On every hit, +1 SG is granted and the counter rolls
## down.
const KILLS_PER_GLORY: int = 200
## "10 SG => 3 EG" conversion ratio.
const EG_PER_10_SG: int = 3


## Grant [param amount] Seasonal Glory to [param guild] and emit any Eternal
## Glory the new total earns through the 10:3 conversion. Caller is responsible
## for persisting the Guild afterward (we batch saves where possible).
static func grant_sg(guild: Resource, amount: int) -> void:
	if guild == null or amount <= 0:
		return
	guild.seasonal_glory += amount
	guild.total_sg_ever += amount
	# Recompute EG target from scratch so we can never under- or over-grant.
	@warning_ignore("integer_division")
	var eg_target: int = (guild.total_sg_ever / 10) * EG_PER_10_SG
	if eg_target > guild.eternal_glory:
		guild.eternal_glory = eg_target


## Hook called from HostileNpc._reward_killer. If the killing player's guild
## owns a territory that contains them at this moment, credit one tick of the
## 200-kill milestone. Solo (guildless) kills are ignored.
static func on_pve_kill(killer: Player) -> void:
	if killer == null or killer.player_resource == null:
		return
	var guild_id: int = killer.player_resource.active_guild_id
	if guild_id <= 0:
		return
	var instance_map: Map = killer.get_parent() as Map
	if instance_map == null:
		return
	var owned: TerritoryFlag = _find_owned_territory_containing(instance_map, guild_id, killer)
	if owned == null:
		return
	_credit_kill(guild_id)


## Iterate every charged flag across every instance and grant TERRITORY_TICK_SG
## to each owning guild per held flag. Guilds are loaded once per tick and
## saved once at the end, so DB cost is O(unique-owning-guilds) per tick — at
## the alpha scale this is essentially free.
static func tick_all_territories(world_server: Node) -> void:
	if world_server == null or world_server.instance_manager == null:
		return
	var guilds_to_save: Dictionary = {} # guild_id -> Resource
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
				var guild: Resource = guilds_to_save[gid]
				if guild == null:
					continue
				grant_sg(guild, TERRITORY_TICK_SG)
				ticks_by_guild[gid] = int(ticks_by_guild.get(gid, 0)) + TERRITORY_TICK_SG

	for gid in guilds_to_save:
		var guild: Resource = guilds_to_save[gid]
		if guild == null:
			continue
		world_server.database.save_guild(guild)
		_announce_tick(world_server, guild, int(ticks_by_guild.get(gid, 0)))


# --- internals ---

static func _find_owned_territory_containing(instance_map: Map, guild_id: int, body: Node2D) -> TerritoryFlag:
	for flag: TerritoryFlag in instance_map.territory_flags.values():
		if flag.owner_guild_id == guild_id and flag.is_body_in_territory(body):
			return flag
	return null


static func _credit_kill(guild_id: int) -> void:
	var ws: Node = ServerHub.current
	if ws == null:
		return
	var guild: Resource = ws.database.get_guild(guild_id)
	if guild == null:
		return
	guild.kill_counter_for_glory += 1
	# Multiple grants in a single call would be unusual (one kill = one credit)
	# but the math handles it: integer division, then roll the counter down.
	@warning_ignore("integer_division")
	var grants: int = guild.kill_counter_for_glory / KILLS_PER_GLORY
	if grants > 0:
		guild.kill_counter_for_glory -= grants * KILLS_PER_GLORY
		grant_sg(guild, grants)
		_announce_milestone(ws, guild, grants)
	ws.database.save_guild(guild)


static func _announce_tick(ws: Node, guild: Resource, sg_gained: int) -> void:
	if ws.chat_service == null or sg_gained <= 0:
		return
	var msg: String = "🏛 Your guild earned %d Seasonal Glory from held territory." % sg_gained
	_push_to_guild_members(ws, guild.guild_id, msg)


static func _announce_milestone(ws: Node, guild: Resource, sg_gained: int) -> void:
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
