class_name CombatHit
## The single place every melee / projectile hitbox routes a hit through, so the
## target rules (flags, PvP zones, sparring, guild friendly-fire) and the shared
## collision mask live in ONE spot. Adding a new weapon means "spawn an Area2D
## with TARGET_MASK and call try_damage" — it can't forget the flag path or the
## friendly-fire gate the way each hitbox used to re-implement them.

## Collision mask every combat hitbox should use (Area2D.collision_mask): the
## layers holding combatants, territory flags, and solid environment. Authored
## scenes (melee_arc.tscn / pick_arc.tscn) already use 7; projectiles set it from
## here so they all detect the same things.
const TARGET_MASK: int = 7

## Damage types. Physical is mitigated by ARMOR, magic by MR — pass the right
## one to try_damage (melee/arrows default to physical; wand bolts send magic).
const DAMAGE_PHYSICAL: StringName = &"physical"
const DAMAGE_MAGIC: StringName = &"magic"

enum Result {
	IGNORED,  ## pass through — not a valid target (self, friendly, safe zone…)
	DAMAGED,  ## a combatant or flag took the hit
	BLOCKED,  ## a solid non-combatant (wall / door) — a projectile should stop here
}


## Resolve a hit on [param body] from [param source] for [param damage]. Applies
## the damage when valid and returns how the caller should react: a projectile
## queue_frees on DAMAGED/BLOCKED and passes through on IGNORED; a melee arc just
## ignores the result and lets the damage land. Server-authoritative — call only
## where damage is owned (the hitboxes already gate on multiplayer.is_server()).
static func try_damage(source: Character, body: Node2D, damage: float, damage_type: StringName = DAMAGE_PHYSICAL) -> Result:
	if body == source:
		return Result.IGNORED

	# Flags: a guilded player damages them directly (capture system); anyone else
	# passes through. Bypasses the character-vs-character rules.
	if body is TerritoryFlag:
		if source is Player:
			(body as TerritoryFlag).take_damage(damage, source)
			return Result.DAMAGED
		return Result.IGNORED

	# A solid body that isn't a combatant = environment (wall / door): blocks
	# projectiles, deals no damage.
	if body is not Character:
		return Result.BLOCKED

	# No NPC-vs-NPC friendly fire (until proper teams exist).
	if source is not Player and body is not Player:
		return Result.IGNORED

	# Player-vs-player only lands in PvP zones — exception for a live sparring match.
	if body is Player and source is Player and not (body as Player).is_pvp():
		if not SparringService.can_spar_damage(source as Player, body as Player):
			return Result.IGNORED

	# Guild friendly fire: members tagged into the same guild don't damage each
	# other, except in a live sparring match (a consented duel still lands).
	if _same_guild_no_spar(source, body):
		return Result.IGNORED

	body.take_damage(damage, source, damage_type)
	return Result.DAMAGED


## The single melee-detection path. Server-only. Runs a deterministic physics
## shape query against [param hitbox]'s "CollisionShape2D" child and returns the
## bodies currently inside it. Every melee weapon (sword, pickaxe, sickle, …)
## routes through this, so they all hit the same things — STILL targets included
## (a territory flag, a motionless mob), which an Area2D's enter-events and
## get_overlapping_bodies() miss for a hitbox spawned on top of them. Must be
## called from _physics_process (direct_space_state is only valid during physics).
static func overlapping_bodies(hitbox: Area2D) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var shape_node: CollisionShape2D = hitbox.get_node_or_null(^"CollisionShape2D")
	if shape_node == null or shape_node.shape == null:
		return out
	var space: PhysicsDirectSpaceState2D = hitbox.get_world_2d().direct_space_state
	if space == null:
		return out
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform
	params.collision_mask = hitbox.collision_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	for hit: Dictionary in space.intersect_shape(params, 16):
		var collider: Object = hit.get("collider")
		if collider is Node2D:
			out.append(collider as Node2D)
	return out


static func _same_guild_no_spar(source: Node, body: Node) -> bool:
	if source is not Player or body is not Player:
		return false
	# Projectiles run this on the client too (visual stop), where a Player's
	# server-owned player_resource can be null — guard rather than deref-crash.
	var src_res: PlayerResource = (source as Player).player_resource
	var tgt_res: PlayerResource = (body as Player).player_resource
	if src_res == null or tgt_res == null:
		return false
	var src_guild: int = src_res.active_guild_id
	var tgt_guild: int = tgt_res.active_guild_id
	if src_guild <= 0 or src_guild != tgt_guild:
		return false
	return not SparringService.can_spar_damage(source as Player, body as Player)


## True if [param healer] may HEAL [param target]: spar teammates while either is
## in a match (so you can't heal across a duel or buff a fighter from the
## sidelines), guildmates otherwise — the same definition the team-colored health
## bars use. THE single source of truth for "who is a heal ally": HealBolt and the
## channeled HealingAuraAbility both defer here so the rule can't drift. Whether
## the caster heals THEMSELF is the caller's call (both treat self as always valid).
static func is_heal_ally(healer: Player, target: Player) -> bool:
	if healer == null or target == null:
		return false
	if healer.player_resource == null or target.player_resource == null:
		return false
	if healer.player_resource.in_match or target.player_resource.in_match:
		return SparringService.are_spar_teammates(healer, target)
	var guild: int = healer.player_resource.active_guild_id
	return guild > 0 and guild == target.player_resource.active_guild_id
