class_name Firefly
extends Node2D
## A drifting glow that casts real light — for night forests / dark glades / caves. Place
## one or a cluster in a map; each gently wanders around its placed position and softly
## pulses, so a group reads as fireflies. Purely cosmetic + client-side: it self-frees on a
## headless server. It doesn't need the day/night tint to exist, but it only READS as light
## against a dark ambient — so it shines in dark maps / at night, and washes out in daylight.

## How far it drifts from its placed position (px).
@export var wander_radius: float = 24.0
## Drift speed multiplier.
@export var wander_speed: float = 0.6
## Light-brightness pulse: speed (rad/s) and depth (fraction of the base energy).
@export var pulse_speed: float = 2.0
@export var pulse_amount: float = 0.25

@onready var _light: PointLight2D = $Light

var _home: Vector2
var _phase: float
var _base_energy: float


func _ready() -> void:
	# Headless server has nothing to render.
	if not GameMode.is_client():
		queue_free()
		return
	_home = position
	_phase = randf() * TAU # desync each firefly so a cluster doesn't pulse in lockstep
	_base_energy = _light.energy


func _process(delta: float) -> void:
	_phase += delta
	# Lissajous wander around home: different X/Y frequencies never line up exactly, so the
	# path looks organic instead of a plain circle.
	var t: float = _phase * wander_speed
	position = _home + Vector2(cos(t * 1.3), sin(t)) * wander_radius
	_light.energy = _base_energy * (1.0 + sin(_phase * pulse_speed) * pulse_amount)
