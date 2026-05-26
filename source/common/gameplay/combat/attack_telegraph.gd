class_name AttackTelegraph
extends Node2D
## A brief red circle shown at an enemy's melee range when it swings. Purely a client
## visual (spawned via the container's rp_attack op) — never affects gameplay.

var radius: float = 20.0

const DURATION: float = 0.35
var _elapsed: float = 0.0


func _ready() -> void:
	z_index = -1 # behind the character sprite


func _process(delta: float) -> void:
	_elapsed += delta
	modulate.a = clampf(1.0 - _elapsed / DURATION, 0.0, 1.0)
	queue_redraw()
	if _elapsed >= DURATION:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.15, 0.15, 0.35))
