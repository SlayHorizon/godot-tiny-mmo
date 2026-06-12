class_name AttackTelegraph
extends Node2D
## A brief red danger-zone preview. Two shapes:
##  - CIRCLE (default): an enemy's melee range when it swings.
##  - CORRIDOR: set [member line_to] — a capsule from this node's position to
##    the dash landing point (the lunge path), so players see WHO is charging
##    and exactly which strip of ground to vacate.
## Purely a client visual (spawned via the container's rp_ ops) — never affects
## gameplay.

const COLOR: Color = Color(1.0, 0.15, 0.15, 0.35)

var radius: float = 20.0
## Lifetime of the fade. Default suits a quick melee swing flash; longer-lived
## telegraphs (the lunge's dodge zone) set it to windup + travel time.
var duration: float = 0.35
## Non-zero = corridor mode: a capsule from local origin to this point, with
## [member radius] as its half-width.
var line_to: Vector2 = Vector2.ZERO

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = -1 # behind the character sprite


func _process(delta: float) -> void:
	_elapsed += delta
	modulate.a = clampf(1.0 - _elapsed / duration, 0.0, 1.0)
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	if line_to == Vector2.ZERO:
		draw_circle(Vector2.ZERO, radius, COLOR)
		return
	# Capsule: rectangle along the dash path + a cap on each end. The landing
	# cap doubles as the "stand here and get hit" marker.
	var side: Vector2 = line_to.normalized().orthogonal() * radius
	draw_colored_polygon(
		PackedVector2Array([side, line_to + side, line_to - side, -side]),
		COLOR
	)
	draw_circle(Vector2.ZERO, radius, COLOR)
	draw_circle(line_to, radius, COLOR)
