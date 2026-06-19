class_name Campfire
extends Node2D
## An animated campfire that casts a warm, flickering light — place it in dark maps (a night
## forest, a camp, a cave). Two looping AnimatedSprite2D layers (logs + flame, autoplayed)
## plus a PointLight2D whose energy wavers like a real fire. Cosmetic + client-side: it
## self-frees on a headless server, and (like the firefly) only reads against a dark ambient.

## Flicker: how fast the light wavers and how deep (as a fraction of the light's base energy).
@export var flicker_speed: float = 7.0
@export var flicker_amount: float = 0.18

@onready var _light: PointLight2D = $Light

var _phase: float
var _base_energy: float


func _ready() -> void:
	# Headless server has nothing to render (and the sprite layers autoplay on their own).
	if not GameMode.is_client():
		queue_free()
		return
	_phase = randf() * TAU # desync multiple campfires so they don't flicker in lockstep
	_base_energy = _light.energy


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	# Two detuned sines sum into a non-repeating, fire-like waver (cheaper than noise).
	var flicker: float = sin(_phase) * 0.6 + sin(_phase * 2.3 + 1.7) * 0.4
	_light.energy = _base_energy * (1.0 + flicker * flicker_amount)
