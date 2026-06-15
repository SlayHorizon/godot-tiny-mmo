class_name CastTelegraph
extends Node2D
## A "danger is coming" ground marker for a TELEGRAPHED ability (Earthshatter's
## wind-up). A red zone that fills as the cast completes, with a sweeping wedge
## that closes like a clock — so a target can read "get out of this circle
## before it fills." Vanishes exactly when the hit lands (the impact ring takes
## over). Deliberately a DIFFERENT visual language from SlamImpact: a telegraph
## FILLS before the hit (dodge), an impact ring EXPANDS after (already happened).
## Pure client visual; frees itself.

const COLOR: Color = Color(0.95, 0.22, 0.2)

## Danger radius — match the ability's hitbox so what's marked is what hits.
var radius: float = 32.0
## How long the wind-up lasts (= the ability's cast time).
var duration: float = 0.8

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = -1 # on the ground, under characters


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	# Filling tint — faint at first, deepening as the strike nears.
	draw_circle(Vector2.ZERO, radius, Color(COLOR, 0.10 + 0.32 * t))
	# Outline that intensifies.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(COLOR, 0.55 + 0.45 * t), 2.0, true)
	# Clock-wedge that sweeps to full as the cast completes — the countdown read.
	if t < 1.0:
		draw_arc(Vector2.ZERO, radius * 0.9, -PI / 2.0, -PI / 2.0 + TAU * t, 40, Color(COLOR, 0.9), 3.0)
