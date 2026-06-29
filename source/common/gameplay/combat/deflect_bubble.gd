class_name DeflectBubble
extends Area2D
## A brief blue parry bubble around the wielder — the sword Deflect. Any projectile
## that enters is DESTROYED: the bubble sits on the HURTBOX layer, so a projectile's
## shape query treats it like a tiny wall and BLOCKS on it (see CombatHit.try_damage's
## "body is not Character -> BLOCKED" path). It runs on EVERY peer, so each client pops
## its own local arrow copy at the bubble's edge while the server's bubble cancels the
## real damage — no "ghost arrow keeps flying" desync. It does NOT block movement
## (character navigation bodies mask WORLD, not HURTBOX). Cosmetic + functional in one.
##
## Spawned by DeflectAbility on every peer (and PREDICTED on the caster for instant
## feedback). Self-frees after [member duration]; the visible radius IS the parry range.

var radius: float = 45.0
var duration: float = 0.45
var color: Color = Color(0.42, 0.66, 1.0)

var _elapsed: float = 0.0


func _ready() -> void:
	# Sit on the HURTBOX layer (projectiles target it) but detect nothing ourselves.
	collision_layer = PhysicsLayers.HURTBOX
	collision_mask = 0
	z_index = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	var life: float = clampf(_elapsed / maxf(0.01, duration), 0.0, 1.0)
	# Snap in fast (a parry is instant), fade out over the tail.
	var edge: float = minf(life * 8.0, minf((1.0 - life) * 3.0, 1.0))
	var shimmer: float = 0.85 + 0.15 * sin(_elapsed * 26.0)
	var a: float = edge * shimmer
	# A soft fill + a bright rim ring = a dome bubble (reads as reflect/immunity).
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.10 * a))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 44, Color(color.r, color.g, color.b, 0.75 * a), 2.5, true)
	draw_arc(Vector2.ZERO, radius - 3.0, 0.0, TAU, 44, Color(1, 1, 1, 0.22 * a), 1.0, true)
