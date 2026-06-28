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
	parent.add_child(fx)
	return fx


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true
	# A one-shot: the "default" anim is authored non-looping, so animation_finished
	# fires once at the end. queue_free then (a Timer fallback would be needed only
	# if we ever loop; we don't here).
	animation_finished.connect(queue_free)
	play(&"default")
