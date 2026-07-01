class_name LashVisual
extends Node2D
## The Lightning Lash beam VFX: a looping lightning bolt extending in the caster's LIVE aim
## direction, read from the synced hand pivot (+ flip) every frame — so it SWEEPS with the
## cursor, matching where the damage beam fires. A child of the caster, named "ChannelVisual"
## so channel.end frees it. Client-side, cosmetic; mirrors the server hitbox in LightningLashAbility.

var beam_length: float = 120.0
var _sprite: AnimatedSprite2D


static func make(player: Node, frames: SpriteFrames, beam_len: float, frame_px: float = 256.0) -> LashVisual:
	var lv: LashVisual = LashVisual.new()
	lv.name = "ChannelVisual"
	lv.beam_length = beam_len
	var s: AnimatedSprite2D = AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.centered = true
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = 1
	var sc: float = beam_len / frame_px  # scale the sheet's frame width to the beam reach
	s.scale = Vector2(sc, sc)
	lv._sprite = s
	lv.add_child(s)
	player.add_child(lv)
	s.play(&"default")
	return lv


func _process(_delta: float) -> void:
	var c: Character = get_parent() as Character
	if c == null or _sprite == null or c.hand_pivot == null:
		return
	# Live world aim: read hand_pivot.rotation (the LOCAL player updates this directly each
	# frame; remotes get it via the pivot sync) — NOT the `pivot` var, which is only SENT, not
	# applied back, on the local player. Un-flip the x like the server beam does.
	var aim: Vector2 = Vector2.from_angle(c.hand_pivot.rotation)
	if c.flipped:
		aim.x = -aim.x
	_sprite.rotation = aim.angle()
	_sprite.position = aim * (beam_length / 2.0)  # centred half-way down the beam
