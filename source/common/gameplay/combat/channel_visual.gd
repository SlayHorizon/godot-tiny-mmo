class_name ChannelVisual
extends Node2D
## Client-side cast visual for an active channel (see [ChannelAbility]). Attached
## to the casting Character on the channel.start push and removed on channel.end
## (or self-expires at duration as a safety net). Renders the &"heal_aura" look —
## a soft green pulsing ground ring sized to the heal radius, so allies can read
## "stand here to be healed." Pure visual; add a branch per [member kind] as more
## channels ship (recall = a cast bar + rune, etc.).

const HEAL_TINT: Color = Color(0.35, 1.0, 0.5)

var duration: float = 6.0
var radius: float = 60.0
var kind: StringName = &"heal_aura"

var _elapsed: float = 0.0


func _ready() -> void:
	# Aura/ground effects sit under the character; the recall cast bar sits above
	# it (a head-height progress read, like the chat bubble's layer).
	z_index = 5 if (kind == &"recall" or kind == &"equip") else -1
	if kind == &"heal_aura":
		_spawn_motes()


## Soft green motes that rise and fade across the aura — the "life returning"
## particle layer (web-safe CPUParticles2D, like the slam debris). Emits
## continuously for the channel's life; stops when this node frees.
func _spawn_motes() -> void:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.emitting = true
	p.amount = 14
	p.lifetime = 1.4
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.9
	p.direction = Vector2(0, -1)
	p.spread = 12.0
	p.gravity = Vector2(0, -16.0) # drift gently upward
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 24.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([
		Color(HEAL_TINT, 0.0), Color(HEAL_TINT, 0.7), Color(HEAL_TINT, 0.0),
	]) # fade in as they lift, fade out at the top
	p.color_ramp = ramp
	add_child(p)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free() # safety — the channel.end push normally frees us first


func _draw() -> void:
	match kind:
		&"recall":
			_draw_recall()
		&"equip":
			_draw_equip()
		_:
			_draw_heal_aura()


## A cool-blue recall: counter-spinning ground runes + a head-height bar that
## fills as the channel completes (the "seconds to town" read).
func _draw_recall() -> void:
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var rune: Color = Color(0.5, 0.75, 1.0)
	var spin: float = _elapsed * 1.5
	draw_arc(Vector2.ZERO, radius, spin, spin + TAU * 0.85, 40, Color(rune, 0.5), 2.0, true)
	draw_arc(Vector2.ZERO, radius * 0.6, -spin, -spin + TAU * 0.7, 32, Color(rune, 0.7), 2.0, true)
	# Over-head fill bar.
	const BAR_W: float = 44.0
	const BAR_H: float = 5.0
	var top_left: Vector2 = Vector2(-BAR_W * 0.5, -52.0)
	draw_rect(Rect2(top_left, Vector2(BAR_W, BAR_H)), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(top_left, Vector2(BAR_W * t, BAR_H)), Color(rune, 0.95))
	draw_rect(Rect2(top_left, Vector2(BAR_W, BAR_H)), Color(rune, 0.55), false, 1.0)


## A neutral amber draw bar over the head — the "drawing my weapon" read. No
## ground runes (equipping isn't a grounded channel), just the timed fill.
func _draw_equip() -> void:
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var col: Color = Color(1.0, 0.82, 0.35)
	const BAR_W: float = 40.0
	const BAR_H: float = 5.0
	var top_left: Vector2 = Vector2(-BAR_W * 0.5, -52.0)
	draw_rect(Rect2(top_left, Vector2(BAR_W, BAR_H)), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(top_left, Vector2(BAR_W * t, BAR_H)), Color(col, 0.95))
	draw_rect(Rect2(top_left, Vector2(BAR_W, BAR_H)), Color(col, 0.55), false, 1.0)


func _draw_heal_aura() -> void:
	# A gentle breathing pulse so it reads as a sustained, friendly effect —
	# deliberately unlike the sharp one-shot expand of an impact ring.
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * 4.0)
	var fill_a: float = 0.06 + 0.05 * pulse
	draw_circle(Vector2.ZERO, radius, Color(HEAL_TINT, fill_a))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(HEAL_TINT, 0.5 + 0.3 * pulse), 2.0, true)
	# A rising inner ring — cheap "life lifting back up" read without particles.
	var t: float = fposmod(_elapsed * 0.6, 1.0)
	var inner: float = lerpf(radius * 0.2, radius * 0.85, t)
	draw_arc(Vector2.ZERO, inner, 0.0, TAU, 40, Color(HEAL_TINT, 0.35 * (1.0 - t)), 1.5, true)
