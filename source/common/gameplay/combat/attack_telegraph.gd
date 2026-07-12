class_name AttackTelegraph
extends CanvasGroup
## A brief red danger-zone preview. Two shapes:
##  - CIRCLE (default): an enemy's melee range when it swings.
##  - CORRIDOR: set [member line_to] — a capsule from this node's position to
##    the dash landing point (the lunge path), so players see WHO is charging
##    and exactly which strip of ground to vacate.
## Purely a client visual (spawned via the container's rp_ ops) — never affects
## gameplay.
##
## CanvasGroup on purpose (owner call 2026-07-09): the corridor is THREE
## overlapping primitives (rect + two end caps). Drawn translucent directly,
## the overlaps double-blend into visible seams; the group flattens the
## opaque shapes into one buffer first and the alpha applies ONCE, uniformly.

## Opaque — transparency is applied at the GROUP level via self_modulate.
const COLOR: Color = Color(1.0, 0.15, 0.15)
const BASE_ALPHA: float = 0.35

var radius: float = 20.0
## Lifetime of the fade. Default suits a quick melee swing flash; longer-lived
## telegraphs (the lunge's dodge zone) set it to windup + travel time.
var duration: float = 0.35
## Non-zero = corridor mode: a capsule from local origin to this point, with
## [member radius] as its half-width.
var line_to: Vector2 = Vector2.ZERO

var _elapsed: float = 0.0
var _drawer: Node2D


func _ready() -> void:
	z_index = -1 # behind the character sprite
	self_modulate.a = BASE_ALPHA
	# Shapes draw on a CHILD so they're captured by the group buffer (the
	# group's own draw commands are not).
	_drawer = _TelegraphDrawer.new()
	_drawer.telegraph = self
	add_child(_drawer)


func _process(delta: float) -> void:
	_elapsed += delta
	self_modulate.a = BASE_ALPHA * clampf(1.0 - _elapsed / duration, 0.0, 1.0)
	_drawer.queue_redraw()
	if _elapsed >= duration:
		queue_free()


class _TelegraphDrawer extends Node2D:
	var telegraph: AttackTelegraph

	func _draw() -> void:
		if telegraph.line_to == Vector2.ZERO:
			draw_circle(Vector2.ZERO, telegraph.radius, AttackTelegraph.COLOR)
			return
		# Capsule: rectangle along the dash path + a cap on each end. The
		# landing cap doubles as the "stand here and get hit" marker.
		var side: Vector2 = telegraph.line_to.normalized().orthogonal() * telegraph.radius
		draw_colored_polygon(
			PackedVector2Array([side, telegraph.line_to + side, telegraph.line_to - side, -side]),
			AttackTelegraph.COLOR
		)
		draw_circle(Vector2.ZERO, telegraph.radius, AttackTelegraph.COLOR)
		draw_circle(telegraph.line_to, telegraph.radius, AttackTelegraph.COLOR)
