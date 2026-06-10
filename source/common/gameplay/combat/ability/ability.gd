class_name AbilityResource
extends Resource
## Base of every weapon action. There is deliberately NO "basic attack vs
## ability" split — a basic attack is just an ability with mana_cost 0. That
## one rule keeps the whole layer uniform: ABILITY_HASTE shortens every
## cooldown (it IS attack speed for basics and cooldown reduction for
## specials), and mana only gates the actions that declare a cost.


@export var name: String
@export var cooldown: float = 1.0
## Mana cost. 0 = free (basic attacks). Checked in can_use (client predicts with
## its synced mana; server is authoritative) and consumed server-side by the
## weapon right after use.
@export var mana_cost: int = 0

## Two-phase abilities (charge weapons) set this true in _init: use_ability is
## the PRESS (begin charging) and release_ability the RELEASE (fire). The weapon
## applies cooldown + mana on the completing phase only. Single-phase abilities
## leave it false and everything behaves as before.
var has_release: bool = false

var last_action_time: float = -INF


func use_ability(_entity: Entity, _direction: Vector2) -> void:
	pass


## Second phase of a two-phase ability (the release/fire). No-op unless
## has_release. Gated by can_use_release, not can_use.
func release_ability(_entity: Entity, _direction: Vector2) -> void:
	pass


## Whether the release phase may fire right now (e.g. "currently charging").
func can_use_release() -> bool:
	return false


## Client-side prediction hook: flip local release-state at SEND time without
## running effects (the server echo runs the real release). Without this, a
## rate-limited/lost echo strands the local copy "charging" forever and the
## weapon bricks until relog.
func predict_release() -> void:
	pass


## [param user] enables the mana check + haste-adjusted cooldown. Null skips
## both (legacy callers keep the plain cooldown gate).
func can_use(user: Entity = null) -> bool:
	if (Time.get_ticks_msec() / 1000.0) - last_action_time < effective_cooldown(user):
		return false
	if mana_cost > 0 and user is Character:
		if (user as Character).stats_component.get_stat(Stat.MANA) < mana_cost:
			return false
	return true


## Cooldown shortened by the wielder's ABILITY_HASTE (LoL-style: 100 haste =
## twice as fast). Diminishing by construction, so stacking it can't hit zero.
func effective_cooldown(user: Entity = null) -> float:
	if user is Character:
		var haste: float = (user as Character).stats_component.get_stat(Stat.ABILITY_HASTE)
		if haste > 0.0:
			return cooldown / (1.0 + haste / 100.0)
	return cooldown


func mark_used():
	last_action_time = Time.get_ticks_msec() / 1000.0
