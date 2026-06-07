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
static func try_damage(source: Character, body: Node2D, damage: float) -> Result:
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
		if not (SparringService.is_pvp_live_for(body as Player) and SparringService.is_pvp_live_for(source as Player)):
			return Result.IGNORED

	# Guild friendly fire: members tagged into the same guild don't damage each
	# other, except in a live sparring match (a consented duel still lands).
	if _same_guild_no_spar(source, body):
		return Result.IGNORED

	body.take_damage(damage, source)
	return Result.DAMAGED


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
	return not (SparringService.is_pvp_live_for(body as Player) and SparringService.is_pvp_live_for(source as Player))
