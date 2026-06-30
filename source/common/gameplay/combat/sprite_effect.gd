class_name SpriteEffect
extends AnimatedSprite2D
## Fire-and-forget client VFX: plays a SpriteFrames "default" animation once, then
## frees itself. The reusable playback node for the external animated spritesheets
## (paladin / priest packs) — drop a SpriteFrames in and call [method spawn].
##
## Client-only by intent (a visual flourish). Spawn it as a child of the node it
## should ride — a Player renders it fine (the replicated-MOB modulate/scale gotcha
## in docs/replicated_props_vfx.md is specific to SubViewport mob rendering, not
## players). Pixel-art crisp via nearest filtering.


# A grayscale-lerp canvas shader: modulate can DIM/tint but can't pull colour OUT
# of a gold sheet, so a saturation < 1 (gray tier-1 shields) needs this.
const _SAT_SHADER_CODE: String = "shader_type canvas_item;\nuniform float saturation : hint_range(0.0, 1.0) = 1.0;\nvoid fragment() {\n\tvec4 t = texture(TEXTURE, UV);\n\tfloat g = dot(t.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(vec3(g), t.rgb, saturation), t.a) * COLOR;\n}"
static var _sat_shader: Shader


## Spawn a configured one-shot under [param parent] and start it. opts keys:
## scale: Vector2, modulate: Color, offset: Vector2, z_index: int,
## speed_scale: float (1.0 = the SpriteFrames' authored fps),
## saturation: float (1.0 = full colour, 0.0 = grayscale). Returns the node.
static func spawn(parent: Node, frames: SpriteFrames, opts: Dictionary = {}) -> SpriteEffect:
	if parent == null or frames == null:
		return null
	var fx: SpriteEffect = SpriteEffect.new()
	fx.sprite_frames = frames
	fx.scale = opts.get("scale", Vector2.ONE)
	fx.modulate = opts.get("modulate", Color.WHITE)
	fx.position = opts.get("offset", Vector2.ZERO)
	fx.z_index = int(opts.get("z_index", 0))
	fx.speed_scale = float(opts.get("speed_scale", 1.0))
	var sat: float = float(opts.get("saturation", 1.0))
	if sat < 1.0:
		if _sat_shader == null:
			_sat_shader = Shader.new()
			_sat_shader.code = _SAT_SHADER_CODE
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = _sat_shader
		mat.set_shader_parameter("saturation", sat)
		fx.material = mat
	fx._loop = bool(opts.get("loop", false))
	fx._hold = bool(opts.get("hold", false))
	fx._spin_deg = float(opts.get("spin_deg_per_sec", 0.0))
	fx._life = float(opts.get("duration", 0.0))
	parent.add_child(fx)
	return fx


# A LOOPING effect replays instead of freeing on finish, and is freed EXTERNALLY
# (e.g. by channel.end) OR after [member _life] seconds if set (a lingering field
# that loops its short anim for a fixed time). _spin_deg rotates it each frame.
# A HOLD effect plays ONCE then sticks on its last frame, freed externally (Battle
# Form's rune builds, then holds at full while the body grows).
var _loop: bool = false
var _hold: bool = false
var _spin_deg: float = 0.0
var _life: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true
	if _loop:
		# Replay on finish; freed by the owner or by _life below.
		animation_finished.connect(func() -> void: play(&"default"))
	elif not _hold:
		animation_finished.connect(queue_free)
	# _hold: do nothing on finish — stick on the last frame until freed externally.
	play(&"default")


func _process(delta: float) -> void:
	if _spin_deg != 0.0:
		rotation += deg_to_rad(_spin_deg) * delta
	if _life > 0.0:
		_age += delta
		if _age >= _life:
			queue_free()
