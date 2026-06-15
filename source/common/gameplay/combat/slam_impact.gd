class_name SlamImpact
extends Node2D
## A ground-impact burst for heavy melee (the hammer slam): a flash core, one or
## more staggered shockwave rings, rock-chunk debris AND a lingering dust puff
## across the hit circle, plus radiating ground cracks that fade. Everything
## scales with the ability's tier (more rings/debris = a bigger hit). Pure
## client visual — spawn it at the impact point and forget it; it frees itself.

const RING_DURATION: float = 0.32
## Delay between successive rings so they ripple instead of overlapping.
const RING_STAGGER: float = 0.08
## How long the ground cracks linger before fading out.
const CRACK_LIFE: float = 0.7
const CRACK_COLOR: Color = Color(0.1, 0.08, 0.07)

## Final radius each shockwave ring + the debris/dust spread reaches — pass the
## slam's reach so the visual matches the hit area.
var max_radius: float = 44.0
## Ring + flash tint (set per ability — T3 runs hotter/redder).
var color: Color = Color(1.0, 0.92, 0.55, 0.9)
## Debris chunks flung up on impact (0 = none). CPUParticles2D, not GPU — it's
## web-export safe.
var debris: int = 0
## How many concentric ripples (1 = a basic hit, 3 = an ultimate).
var ring_count: int = 1

var _elapsed: float = 0.0
var _life: float = RING_DURATION
## Pre-rolled crack polylines ([center, mid, end]) so they're stable per frame.
var _cracks: Array[PackedVector2Array] = []


func _ready() -> void:
	z_index = -1 # on the ground, under characters
	_life = maxf(RING_DURATION + float(maxi(0, ring_count - 1)) * RING_STAGGER, CRACK_LIFE)
	_build_cracks()
	if debris > 0:
		_spawn_debris()
		_spawn_dust()


## Jagged cracks radiating from the impact — count scales with the hit's power.
func _build_cracks() -> void:
	var count: int = ring_count * 3
	for i: int in count:
		var angle: float = randf() * TAU
		var length: float = max_radius * randf_range(0.6, 1.0)
		var mid: Vector2 = Vector2.from_angle(angle + randf_range(-0.3, 0.3)) * (length * 0.5)
		var tip: Vector2 = Vector2.from_angle(angle) * length
		_cracks.append(PackedVector2Array([Vector2.ZERO, mid, tip]))


## Heavy rock chunks: erupt across the whole damage circle, pop up, fall back.
func _spawn_debris() -> void:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = debris
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = max_radius * 0.95
	p.direction = Vector2(0, -1)
	p.spread = 55.0
	p.gravity = Vector2(0, 520.0)
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 120.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	p.color = Color(0.52, 0.43, 0.34)  # dusty rock brown
	add_child(p)


## A soft dust cloud that puffs outward across the circle and lingers/fades —
## the "dirt flying" that sells a shattered ground beyond the hard chunks.
func _spawn_dust() -> void:
	var d: CPUParticles2D = CPUParticles2D.new()
	d.emitting = true
	d.one_shot = true
	d.amount = maxi(6, debris)
	d.lifetime = 0.9
	d.explosiveness = 0.85
	d.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	d.emission_sphere_radius = max_radius
	d.direction = Vector2(0, -1)
	d.spread = 180.0          # puff in every direction
	d.gravity = Vector2(0, -25.0)  # drifts gently UP as it dissipates
	d.initial_velocity_min = 8.0
	d.initial_velocity_max = 38.0
	d.scale_amount_min = 2.0
	d.scale_amount_max = 4.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(0.62, 0.57, 0.5, 0.45))
	ramp.set_color(1, Color(0.62, 0.57, 0.5, 0.0))  # fade to nothing over life
	d.color_ramp = ramp
	add_child(d)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= _life:
		queue_free()


func _draw() -> void:
	# Lingering ground cracks (fade over CRACK_LIFE), drawn first = underneath.
	var crack_a: float = 1.0 - clampf(_elapsed / CRACK_LIFE, 0.0, 1.0)
	if crack_a > 0.0:
		for crack: PackedVector2Array in _cracks:
			draw_polyline(crack, Color(CRACK_COLOR, 0.7 * crack_a), 2.0)

	# Each ring runs its own expand-and-fade, staggered, so multi-ring impacts
	# ripple outward like a real shockwave.
	for i: int in maxi(1, ring_count):
		var rt: float = (_elapsed - float(i) * RING_STAGGER) / RING_DURATION
		if rt < 0.0 or rt > 1.0:
			continue
		var eased: float = 1.0 - pow(1.0 - rt, 3.0)
		var radius: float = lerpf(6.0, max_radius, eased)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, (1.0 - rt) * color.a), lerpf(5.0, 1.0, rt), true)

	# Core flash on the first ring: a bright dot that pops then collapses.
	if _elapsed < RING_DURATION * 0.34:
		var ct: float = _elapsed / (RING_DURATION * 0.34)
		var core: Color = color.lerp(Color(1, 1, 1), 0.6)
		draw_circle(Vector2.ZERO, lerpf(14.0, 2.0, ct), Color(core, (1.0 - ct) * 0.85))
