class_name CombatHit
## The single place every melee / projectile hitbox routes a hit through, so the
## target rules (flags, PvP zones, sparring, guild friendly-fire) and the shared
## collision mask live in ONE spot. Adding a new weapon means "spawn an Area2D
## with TARGET_MASK and call try_damage" — it can't forget the flag path or the
## friendly-fire gate the way each hitbox used to re-implement them.

## Collision mask every combat hitbox uses (Area2D.collision_mask): hurtboxes (damage) +
## territory flags (capture) + world (block). NOT character bodies — those are navigation
## only, so attacks hit the body-sized HurtBox instead. See PhysicsLayers + docs/combat_layers.md.
## Projectiles read this; melee arcs set their mask from PhysicsLayers in their own _ready.
const TARGET_MASK: int = PhysicsLayers.COMBAT_TARGET_MASK

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
	# Combat hitboxes detect a character's HurtBox area (not its navigation body) — resolve
	# the hurtbox to its owning Character so the target rules below work unchanged.
	if body is HurtBox:
		body = (body as HurtBox).character
	if body == null or body == source:
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

	# Player-vs-player: one allegiance + zone + spar gate (see can_damage). Allies
	# never land (guild friendly-fire, spar teammates); a live duel uses spar
	# rules; otherwise open-world PvP needs a PvP zone.
	if source is Player and body is Player:
		if not can_damage(source as Player, body as Player):
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
	params.collide_with_areas = true # also catch HurtBox areas (the hit target), not just bodies
	for hit: Dictionary in space.intersect_shape(params, 16):
		var collider: Object = hit.get("collider")
		if collider is Node2D:
			out.append(collider as Node2D)
	return out


## THE single allegiance check: are these two players ALLIES? Resolved by context,
## highest priority first — a live spar match (teammates only; opponents are NOT
## allies), [future: a shared co-op instance group], otherwise guild. Open-world
## allegiance is purely guild, which is what keeps basing/PvP free of the
## party-vs-guild paradox. Used for healing (HealBolt, HealingAuraAbility) AND,
## inverted, by the damage gate (can_damage), so the rule can never drift apart.
##
## Server-side: reads player_resource (null client-side for remotes → not allied).
## The client health-bar TINT is a parallel peer-id mirror in
## Player._apply_team_bar_color; when a group context ships, sync it there too.
static func are_allied(a: Player, b: Player) -> bool:
	if a == null or b == null:
		return false
	if a == b:
		return true
	if a.player_resource == null or b.player_resource == null:
		return false
	if a.player_resource.in_match or b.player_resource.in_match:
		return SparringService.are_spar_teammates(a, b)
	# Co-op group (dungeon) — groupmates are allies regardless of guild.
	if GroupService.are_grouped(int(a.player_resource.current_peer_id), int(b.player_resource.current_peer_id)):
		return true
	var guild: int = a.player_resource.active_guild_id
	return guild > 0 and guild == b.player_resource.active_guild_id


## Whether [param source] may damage [param target] (player-vs-player only). Allies
## never land a hit; a live spar match defers to the duel rules (opponents in the
## same match, friendly-fire off, countdown over); otherwise it's open-world PvP,
## allowed only when the target is in a PvP zone. NPC / flag / environment cases
## are resolved in try_damage before this is reached.
static func can_damage(source: Player, target: Player) -> bool:
	if source == null or target == null or source == target:
		return false
	if are_allied(source, target):
		return false
	if source.player_resource != null and target.player_resource != null \
			and (source.player_resource.in_match or target.player_resource.in_match):
		return SparringService.can_spar_damage(source, target)
	return target.is_pvp()
