class_name GuardAura
extends Node2D
## Client-side "you are guarding" indicator — a soft blue FLOOR area under the
## player for the duration of a Last Stand buff. Deliberately a flat ground aura,
## NOT a bubble: a bubble reads as damage-immunity/reflect, but Last Stand is just
## bonus armor/MR, so a defensive-coloured stance ring is the honest read. Blue =
## the Resolve/defensive branch, so players learn it by colour. Frees itself after
## [member duration] (the client times it from the cast push — no "buff ended" RPC).

var duration: float = 6.0
var radius: float = 24.0
var color: Color = Color(0.4, 0.62, 1.0)

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = -1  # under the player — a floor aura, not an overlay


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	var life: float = clampf(_elapsed / maxf(0.01, duration), 0.0, 1.0)
	# Ease in over the first ~0.25s and out over the last ~0.25s.
	var edge: float = minf(life * 4.0, minf((1.0 - life) * 4.0, 1.0))
	var pulse: float = 0.85 + 0.15 * sin(_elapsed * 4.0)
	var a: float = edge * pulse
	# Squash to a floor ellipse, centred on the player origin (which sits at the
	# feet — the same spot the heal-aura ring uses, so it reads as a ground ring).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.13 * a))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.55 * a), 2.0, true)
