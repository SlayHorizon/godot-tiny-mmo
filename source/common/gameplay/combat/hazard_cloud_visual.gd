class_name HazardCloudVisual
extends Node2D
## Client-side rendering of a HazardZone (refactor P4): a sickly translucent
## disc that holds while the zone damages and fades out over its last moments.
## Pure visual — the ticking damage is the server's HazardZone; this is spawned
## by the rp_hazard_zone op (docs/replicated_props_vfx.md pattern). Single
## primitive, so no CanvasGroup needed (no overlap seams to hide).

const COLOR: Color = Color(0.55, 0.85, 0.3)
const BASE_ALPHA: float = 0.3
## Fade-out tail at the end of the zone's life.
const FADE_S: float = 0.45

var radius: float = 48.0
var duration_s: float = 3.0

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = -1 # ground decal — under characters, same rule as AttackTelegraph


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration_s:
		queue_free()
		return
	var remaining: float = duration_s - _elapsed
	modulate.a = clampf(remaining / FADE_S, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(COLOR.r, COLOR.g, COLOR.b, BASE_ALPHA))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(COLOR.r, COLOR.g, COLOR.b, BASE_ALPHA * 1.8), 2.0)
