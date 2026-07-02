@tool
@icon("res://assets/node_icons/blue/icon_door.png")
class_name Portal
extends Warper
## A Warper dressed as an animated portal: the swirl sprite + a full HSV recolor + an
## optional destination label + a dwell-then-fade warp transition. All warp behavior is
## inherited — the server only honors [member Warper.warp_delay_s] before firing, so
## doors (delay 0) stay instant. Place it in a map exactly like a plain Warper (set
## target_instance / warper_id / target_id), then pick a color per destination.
## @tool so color + label preview live in the editor while placing.

## Dominant HSV of the source swirl art (weighted by s*v over opaque pixels — measured,
## don't eyeball). portal_color is matched against these: hue ROTATES to the target's
## hue, saturation and value SCALE by target/source. Scaling keeps the art's internal
## shading (bright core, dimmer rim), so a dark pick gives a genuinely dark portal
## instead of the hue-only bright-cyan miss the first iteration had.
const SOURCE_HUE: float = 0.7116
const SOURCE_SAT: float = 0.9219
const SOURCE_VAL: float = 0.8578
## Swirl animation speed while the local player charges the warp (client juice).
const REV_UP_SPEED: float = 2.6
## Screen fade-back-in time once the warp lands (fade-out time = warp_delay_s).
const FADE_IN_S: float = 0.3

## The color the swirl becomes — what you pick is what you get, including dark colors.
## Default = the source art's own color (renders unchanged).
@export var portal_color: Color = Color(0.28, 0.067, 0.858):
	set(value):
		portal_color = value
		_apply()
## Shown under the portal (e.g. "Forest"). Empty = no label.
@export var destination_label: String = "":
	set(value):
		destination_label = value
		_apply()

## Client-side: the screen fade covering the local player's pending warp, if any.
var _fade: WarpFade

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $Label


func _ready() -> void:
	_apply()
	# Client-only transition hooks: fade + rev-up while the LOCAL player stands in the
	# portal. The server enforces the same warp_delay_s dwell independently.
	if not Engine.is_editor_hint() and not multiplayer.is_server():
		body_entered.connect(_on_local_body_entered)
		body_exited.connect(_on_local_body_exited)


## Push color + label onto the child nodes. Safe to call before ready (setters fire on
## scene load, before @onready resolves) — it just no-ops until _ready re-applies.
func _apply() -> void:
	if animated_sprite == null or label == null:
		return
	var material_shader: ShaderMaterial = animated_sprite.material as ShaderMaterial
	if material_shader != null:
		material_shader.set_shader_parameter(&"hue_offset", wrapf(portal_color.h - SOURCE_HUE, 0.0, 1.0))
		material_shader.set_shader_parameter(&"sat_scale", portal_color.s / SOURCE_SAT)
		material_shader.set_shader_parameter(&"val_scale", portal_color.v / SOURCE_VAL)
	label.text = destination_label
	label.visible = not destination_label.is_empty()


func _on_local_body_entered(body: Node2D) -> void:
	if warp_delay_s <= 0.0 or not _is_local_player(body):
		return
	animated_sprite.speed_scale = REV_UP_SPEED
	_fade = WarpFade.new(portal_color, warp_delay_s, FADE_IN_S)
	get_tree().root.add_child.call_deferred(_fade)


func _on_local_body_exited(body: Node2D) -> void:
	if not _is_local_player(body):
		return
	animated_sprite.speed_scale = 1.0
	# Stepped out before the dwell finished: abort the fade (the server cancels its side
	# by re-checking overlap after the dwell). Once the fade-out completed, cancel() is
	# a no-op — that exit is just our own despawn as the warp goes through.
	if _fade != null:
		_fade.cancel()
		_fade = null


## True only on the client that owns [body]: player nodes are named after their peer id,
## and the server's own unique id (1) never names a player.
func _is_local_player(body: Node2D) -> bool:
	return body is Player and body.name.to_int() == multiplayer.get_unique_id()


## Self-contained full-screen fade covering a portal warp: fade to a dark tint of the
## portal color over the dwell, hold through the map switch, fade back in, free itself.
## Lives directly under the tree ROOT so it survives the old map (and the portal that
## spawned it) being freed mid-transition.
class WarpFade extends CanvasLayer:
	var _rect: ColorRect
	var _tween: Tween
	var _color: Color
	var _out_s: float
	var _in_s: float
	var _committed: bool = false

	func _init(portal_color: Color, out_s: float, in_s: float) -> void:
		layer = 100
		_color = Color(portal_color.r * 0.15, portal_color.g * 0.15, portal_color.b * 0.15)
		_out_s = out_s
		_in_s = in_s

	func _ready() -> void:
		_rect = ColorRect.new()
		_rect.color = Color(_color, 0.0)
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rect)
		_tween = create_tween()
		_tween.tween_property(_rect, ^"color:a", 1.0, _out_s)
		_tween.tween_callback(func() -> void: _committed = true)
		# Hold dark through the instance switch, then reveal the destination.
		_tween.tween_interval(0.25)
		_tween.tween_property(_rect, ^"color:a", 0.0, _in_s)
		_tween.tween_callback(queue_free)

	## Abort a not-yet-committed fade (player stepped out during the dwell): reverse
	## quickly and free. After commit (fade-out done, warp firing) this is a no-op.
	func cancel() -> void:
		if _committed:
			return
		_tween.kill()
		var back: Tween = create_tween()
		back.tween_property(_rect, ^"color:a", 0.0, 0.15)
		back.tween_callback(queue_free)
