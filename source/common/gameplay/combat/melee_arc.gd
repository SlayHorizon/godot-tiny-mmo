class_name MeleeArc
extends Area2D
## Short-lived hitbox spawned by melee weapons. Damages every valid target
## it overlaps during its brief lifetime, then frees itself. Honors the same
## PvP / sparring / friendly-fire rules as the bow arrow so combat behaves
## consistently regardless of weapon type.
##
## Server-only logic — clients spawn an empty visual placeholder (the
## CollisionShape and damage path are gated behind multiplayer.is_server()).

## How long the arc stays live before despawning. Short enough to feel like
## a single swing, long enough to forgive timing.
@export var lifetime: float = 0.18

var source: Character
var damage: float = 10.0

## Bodies already damaged this swing, so the spawn-overlap scan and a later
## body_entered don't double-hit the same target.
var _hit_bodies: Array[Node] = []


func _ready() -> void:
	if GameMode.is_world_server():
		body_entered.connect(_on_body_entered)
		_scan_initial_overlaps()

	var t: Timer = Timer.new()
	t.wait_time = lifetime
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()


## body_entered only fires for bodies that ENTER the arc — a hitbox spawned on
## top of a STILL target (e.g. a territory flag, or a motionless mob) would miss
## it. Wait one physics step so the overlap registers, then process current bodies.
func _scan_initial_overlaps() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	for body: Node2D in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if _hit_bodies.has(body):
		return
	_hit_bodies.append(body)
	# All target rules (flags, PvP zones, sparring, guild friendly-fire) live in
	# CombatHit. A swing doesn't "consume" — it damages everything valid in range,
	# so the result is ignored (a wall just resolves to BLOCKED and is skipped).
	CombatHit.try_damage(source if source is Character else null, body, damage)
