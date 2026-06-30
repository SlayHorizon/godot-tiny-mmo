class_name SpinVisual
extends Node2D
## The Whirlwind's looping VFX: spawns OVERLAPPING one-shot slashes, each rotated a
## step further, every [member spawn_interval]. Because a fresh slash starts before
## the previous one fades (the slash's impact is ~frame 6, fade ~frame 7), the sweeps
## blend into a continuous spin — no gap/restart flicker like a single looping sprite.
## Lives on the caster for the channel; freed by channel.end (which frees its in-flight
## slash children too). Client-side, cosmetic.

var frames: SpriteFrames
var vfx_scale: float = 1.0
## Playback speed of each slash (× the SpriteFrames' authored fps). < 1 = slower, so
## each slash LASTS longer and overlaps the next more (no blank gaps). The GIF had no
## baked timing, so this is pure feel.
var slash_speed: float = 0.8
## Spawn the next slash this long after the last — small enough that several are
## always mid-sweep at once (≈ slash duration / 4), so they blend into a smooth spin.
var spawn_interval: float = 0.16
## Degrees each successive slash is rotated, so the sweeps walk around the circle.
var angle_step: float = 100.0

var _angle: float = 0.0
var _timer: float = 0.0


func _ready() -> void:
	_spawn_slash()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= spawn_interval:
		_timer -= spawn_interval
		_spawn_slash()


func _spawn_slash() -> void:
	if frames == null:
		return
	var fx: SpriteEffect = SpriteEffect.spawn(self, frames, {
		"scale": Vector2(vfx_scale, vfx_scale),
		"z_index": 1,
		"speed_scale": slash_speed,
	})
	if fx != null:
		fx.rotation = deg_to_rad(_angle)
	_angle += angle_step
