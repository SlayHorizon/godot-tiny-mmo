class_name MobAttack
extends Resource
## One thing a mob can DO on its swing timer (refactor P2,
## docs/hostile_npc_refactor.md). The chassis keeps the GLOBAL swing rate
## (EnemyTypeResource.attack_cooldown) and, each swing, offers the turn to the
## authored attacks IN ORDER — the first one whose own recharge is up and whose
## target exists takes it. Array order is therefore priority ("heal an ally if
## someone's hurt, otherwise bolt the enemy").
##
## Like MobBehavior, instances are SHARED across every mob of the archetype —
## per-mob runtime scratch (recharge timestamps) lives on the npc, keyed by
## this resource. npc params stay duck-typed (HostileNpc <-> resource compile
## cycle; same dodge as MobBehavior).

## WHO an attack aims at, within the mob's engagement. The chassis still owns
## WHO TO FIGHT (aggro/leash); this only picks the victim of one swing.
enum TargetPolicy {
	NEAREST_ENEMY,
	LOWEST_HP_ENEMY,
	LOWEST_HP_ALLY, ## resolver lands with HealAllyAttack (refactor P3)
}

## This attack's OWN recharge, on top of the global swing rate. 0 = ready
## every swing. A sorcerer's heal at 4.0 fires at most every 4 s while its
## bolt (0) fills every other swing.
@export var cooldown: float = 0.0
@export var target_policy: TargetPolicy = TargetPolicy.NEAREST_ENEMY


## Take the swing if ready. Owns the recharge gate; _fire owns target pick +
## effect and reports whether it actually did anything (a miss doesn't spend
## the recharge, so the next swing retries).
func try_fire(npc, now: int) -> bool:
	var scratch: Dictionary = runtime_state(npc)
	if now < int(scratch.get("ready_at_ms", 0)):
		return false
	if not _fire(npc):
		return false
	scratch["ready_at_ms"] = now + int(cooldown * 1000.0)
	return true


## Subclass hook: pick a target and do the thing. Return false if no valid
## target (lets the next attack in the array take this swing instead).
func _fire(_npc) -> bool:
	return false


## Per-mob scratch for this shared resource (see MobBehavior.runtime_state).
func runtime_state(npc) -> Dictionary:
	return npc.behavior_state.get_or_add(self, {})


## Policy-based enemy pick among everyone the mob can currently strike.
## Returns null when nobody qualifies.
func _pick_enemy(npc) -> Player:
	var best: Player = null
	var best_score: float = INF
	for candidate: Player in npc._strike_candidates():
		if not npc._is_target_valid(candidate) or not npc._is_hostile_to(candidate):
			continue
		var score: float
		if target_policy == TargetPolicy.LOWEST_HP_ENEMY:
			score = candidate.stats_component.get_stat(Stat.HEALTH)
		else:
			score = npc.global_position.distance_to(candidate.global_position)
		if score < best_score:
			best_score = score
			best = candidate
	return best
