class_name SpawnEffect
extends Node2D
## A summon / materialize burst played when a mob appears or respawns: an expanding ember ring, a
## bright core flash, and rising ember particles (web-safe CPUParticles2D). Pure client visual —
## add it as a child of the mob (or drop it at a point) and forget it; it frees itself.
##
## It's a STANDALONE node (the AttackTelegraph / SlamImpact family), NOT a tween on the mob's own
## sprite: a replicated mob's own modulate/scale don't reach its displayed sprite (see
## docs/replicated_props_vfx.md), but a separate node that draws itself renders fine.

const DURATION: float = 0.55

## Radius the ring expands to. Tune per caller if a boss should read bigger.
var radius: float = 26.0
## Ember tint (orange-gold — matches the Ember motif).
var color: Color = Color(1.0, 0.62, 0.24, 0.9)

var _elapsed: float = 0.0


func _ready() -> void:
	_spawn_embers()


## One-shot puff of embers rising as the body forms. CPUParticles2D (not GPU) = web-export safe.
func _spawn_embers() -> void:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 14
	p.lifetime = DURATION
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.6
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.gravity = Vector2(0, -50.0) # embers drift UP
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 75.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.78, 0.35, 0.95))
	ramp.set_color(1, Color(0.7, 0.15, 0.08, 0.0)) # ember -> ash, fades out
	p.color_ramp = ramp
	add_child(p)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= DURATION:
		queue_free()


func _draw() -> void:
	var t: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	# Expanding ring that thins + fades.
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var ring_r: float = lerpf(3.0, radius, eased)
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 40, Color(color, (1.0 - t) * color.a), lerpf(4.0, 1.0, t), true)
	# Bright core flash on the first third — a pop that collapses.
	if t < 0.35:
		var ct: float = t / 0.35
		var core: Color = color.lerp(Color(1.0, 1.0, 1.0), 0.7)
		draw_circle(Vector2.ZERO, lerpf(11.0, 2.0, ct), Color(core, (1.0 - ct) * 0.85))
