class_name MeleeArc
extends Area2D
## Short-lived hitbox spawned (server-only) by melee weapons. Damages every valid
## target it overlaps via CombatHit — same flag / PvP / sparring / friendly-fire
## rules as the bow arrow, so combat stays consistent across weapons.
##
## The arc is a STATIC box at the swing position; it does NOT follow the player
## (a swing is a brief moment in front of you). The visible swing is the weapon's
## own animation, not this node.
##
## Detection goes through CombatHit.overlapping_bodies (a deterministic physics
## shape query) on the first physics step, plus body_entered for anything that
## walks in during its life. The shape query is what lets a swing hit a STILL
## target (a territory flag, a motionless mob) that enter-events miss.

## A target at/below this fraction of max HP counts as "low" for the wielder's
## Executioner mastery passive (DAMAGE_VS_LOW_HP amp).
const LOW_HP_THRESHOLD: float = 0.35

@export var lifetime: float = 0.18

var source: Character
var damage: float = 10.0
## On-hit slow (Crippling Strike): flat move_speed reduction applied as a
## timed negative buff to each Player struck. 0 = no slow. Set by the ability.
var slow_amount: float = 0.0
var slow_duration_s: float = 0.0
## Physical by default (melee). A spell nova (NovaAbility) sets MAGIC so it scales the
## caster's MR-mitigated path instead of armor.
var damage_type: StringName = CombatHit.DAMAGE_PHYSICAL
## Blood Feast drain: each LANDED hit heals + restores mana to the SOURCE (the caster
## feeds on the pack). 0 = none. mana_per_hit only pays out on a real hit, so whiffing
## into air refunds nothing.
var heal_per_hit: float = 0.0
var mana_per_hit: float = 0.0

var _hit_bodies: Array[Node] = []
var _scanned: bool = false


func _ready() -> void:
	collision_mask = PhysicsLayers.COMBAT_TARGET_MASK
	if not GameMode.is_world_server():
		set_physics_process(false)
	else:
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_body_entered) # catch walk-in HurtBox areas too

	var t: Timer = Timer.new()
	t.wait_time = lifetime
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	if _scanned:
		return
	_scanned = true
	for body: Node2D in CombatHit.overlapping_bodies(self):
		_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if _hit_bodies.has(body):
		return
	_hit_bodies.append(body)
	# `body` may be a HurtBox area — resolve to its owner Character for HP / type checks.
	var struck: Node = (body as HurtBox).character if body is HurtBox else body
	var dealt: float = damage * _execute_multiplier(struck)
	var result: CombatHit.Result = CombatHit.try_damage(source if source is Character else null, body, dealt, damage_type)
	if result != CombatHit.Result.DAMAGED:
		return
	# Slow rides a LANDED hit on a Player only (the first negative status buff, via
	# the same BuffService potions use).
	if slow_amount > 0.0 and slow_duration_s > 0.0 and struck is Player:
		BuffService.apply(struck as Player, Stat.MOVE_SPEED, -slow_amount, slow_duration_s)
	# Blood Feast: drain the struck enemy — heal + mana to the source, per landed hit.
	if is_instance_valid(source):
		if heal_per_hit > 0.0:
			var hmax: float = source.stats_component.get_stat(Stat.HEALTH_MAX)
			source.stats_component.set_stat(Stat.HEALTH, minf(hmax, source.stats_component.get_stat(Stat.HEALTH) + heal_per_hit))
		if mana_per_hit > 0.0:
			var mmax: float = source.stats_component.get_stat(Stat.MANA_MAX)
			source.stats_component.set_stat(Stat.MANA, minf(mmax, source.stats_component.get_stat(Stat.MANA) + mana_per_hit))


## Executioner mastery passive: the wielder's DAMAGE_VS_LOW_HP stat (%) amplifies
## damage to targets at/below [constant LOW_HP_THRESHOLD] of max HP. Returns 1.0
## (no change) for anyone without the passive — the stat is 0 by default — so this
## is a cheap no-op on every other hit in the game.
func _execute_multiplier(struck: Node) -> float:
	if not is_instance_valid(source):
		return 1.0
	var amp: float = source.stats_component.get_stat(Stat.DAMAGE_VS_LOW_HP)
	if amp <= 0.0 or struck is not Character:
		return 1.0
	var target: Character = struck as Character
	var max_hp: float = target.stats_component.get_stat(Stat.HEALTH_MAX)
	if max_hp <= 0.0:
		return 1.0
	if target.stats_component.get_stat(Stat.HEALTH) / max_hp <= LOW_HP_THRESHOLD:
		return 1.0 + amp / 100.0
	return 1.0
