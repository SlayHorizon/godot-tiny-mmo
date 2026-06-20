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

@export var lifetime: float = 0.18

var source: Character
var damage: float = 10.0
## On-hit slow (Crippling Strike): flat move_speed reduction applied as a
## timed negative buff to each Player struck. 0 = no slow. Set by the ability.
var slow_amount: float = 0.0
var slow_duration_s: float = 0.0

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
	var result: CombatHit.Result = CombatHit.try_damage(source if source is Character else null, body, damage)
	# Slow rides a LANDED hit on a Player only. `body` may be a HurtBox area — resolve to its
	# owner for the type check (the first negative status buff, via the same BuffService potions use).
	if result == CombatHit.Result.DAMAGED and slow_amount > 0.0 and slow_duration_s > 0.0:
		var struck: Node = (body as HurtBox).character if body is HurtBox else body
		if struck is Player:
			BuffService.apply(struck as Player, Stat.MOVE_SPEED, -slow_amount, slow_duration_s)
