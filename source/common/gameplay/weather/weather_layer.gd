class_name WeatherLayer
extends Node2D
## In-world ambient weather (drifting leaves, rain, fog, cloud shadows...). Client-only;
## created at runtime by Client and parented under it. It follows the local player every
## frame so its particles always blanket the camera view, rendering IN the world — over
## the ground, under the HUD — for the top-down "on the ground" look (inspired by
## NinjaAdventure's camera-grid weather).
##
## Driven by Map.weather, which is an ARRAY so a map can STACK effects (leaves + cloud
## shadows + fog at once) — each entry gets its own CPUParticles2D emitter. Applied on
## every area change via Client._on_instance_changed → apply(); an empty list = clear
## skies. Players can disable the whole layer (perf / preference) from
## Settings ▸ Graphics ▸ Weather Effects — see _on_setting_changed.

## Render above world content but below the HUD (a CanvasLayer at layer 10, which always
## draws over world z-indices).
const Z_INDEX: int = 100
## TOP_FALL particles emit from a wide strip this far ABOVE the player (world px) and fall
## down through the view. Generous so it covers the screen at typical camera zooms.
const EMIT_OFFSET_Y: float = -320.0
const EMIT_HALF_WIDTH: float = 520.0
## For AREA_DRIFT (clouds/fog): also emit across this half-height, blanketing the view.
const AREA_HALF_HEIGHT: float = 360.0
## Settings key gating the whole layer (false = no emitters spawned at all).
const SETTING_SECTION: StringName = &"general"
const SETTING_PROPERTY: StringName = &"weather_effects"
## Native mobile keeps weather but with fewer particles per emitter: it's gl_compatibility
## (CPU particles) on weaker hardware, so thin the counts while leaving desktop's full, lush
## weather untouched. Web does NOT use this — weather is disabled outright there (see _ready),
## because its single-threaded WASM can't absorb the CPU particle cost. Tune if mobile needs lighter.
const CONSTRAINED_AMOUNT_SCALE: float = 0.45

## One live CPUParticles2D per active WeatherResource (effects stack).
var _emitters: Array[CPUParticles2D] = []
## The weather assigned to the current map; kept so a settings toggle can rebuild it.
var _weather: Array[WeatherResource] = []
## Mirror of the Settings toggle; when false no emitters exist (zero CPU cost).
var _enabled: bool = true
## Per-platform multiplier on each emitter's particle count (1.0 desktop, reduced on
## web/mobile). Set once in _ready — the platform can't change at runtime.
var _amount_scale: float = 1.0


func _ready() -> void:
	# Headless server has nothing to render.
	if not GameMode.is_client():
		set_process(false)
		queue_free()
		return
	z_index = Z_INDEX
	# Web is single-threaded (no SharedArrayBuffer on itch for broad browser support), so CPU
	# particle simulation would fight all game logic on one thread. Weather is the heaviest
	# tenant, so it's cut entirely there: the browser build is the "lite" version, and the
	# download carries full weather. Stay fully inert — never spawn, never tick, and don't
	# listen for the toggle (which is hidden on web anyway).
	if OS.has_feature("web"):
		_enabled = false
		set_process(false)
		return
	# Native mobile is multi-core but still gl_compatibility on weaker hardware: keep the
	# weather, just thin the per-emitter counts.
	if OS.has_feature("mobile"):
		_amount_scale = CONSTRAINED_AMOUNT_SCALE
	var saved: Variant = ClientState.settings.get_value(SETTING_SECTION, SETTING_PROPERTY)
	_enabled = true if saved == null else bool(saved)
	ClientState.settings.setting_changed.connect(_on_setting_changed)


func _process(_delta: float) -> void:
	# Follow the local player so the effect always blankets the camera view.
	var local_player: Node2D = ClientState.local_player
	if local_player != null:
		global_position = local_player.global_position


## Replace the active weather with [param weather_list] — each entry is one stacked
## effect. Pass an empty array for clear skies. Safe to call on every map change.
func apply(weather_list: Array[WeatherResource]) -> void:
	_weather = weather_list.duplicate() # snapshot — don't alias the map resource's array
	_rebuild()


## Tear down every emitter and recreate one per active effect. Skipped entirely when the
## player has weather disabled. Called on map change and when the settings toggle flips.
func _rebuild() -> void:
	for emitter: CPUParticles2D in _emitters:
		emitter.queue_free()
	_emitters.clear()
	if not _enabled:
		return
	for weather: WeatherResource in _weather:
		if weather == null:
			continue
		var emitter: CPUParticles2D = _make_emitter(weather)
		add_child(emitter)
		_emitters.append(emitter)


## Build one fully-configured emitter for [param weather]. local_coords = false so the
## particles stay put in the world while this node follows the player.
func _make_emitter(weather: WeatherResource) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.texture = weather.texture
	p.color = weather.color
	p.amount = maxi(1, int(round(weather.amount * _amount_scale)))
	p.lifetime = maxf(0.1, weather.lifetime)
	p.spread = weather.spread_degrees
	# TOP_FALL rains down from a strip above the view, accelerating under gravity (leaves,
	# rain). AREA_DRIFT scatters across the whole view and drifts at a CONSTANT slow
	# velocity (cloud shadows, fog) so they never visibly speed up.
	var drift: Vector2 = Vector2(weather.wind, weather.fall_speed)
	if weather.emit_mode == WeatherResource.EmitMode.AREA_DRIFT:
		p.position = Vector2.ZERO
		p.emission_rect_extents = Vector2(EMIT_HALF_WIDTH, AREA_HALF_HEIGHT)
		var speed: float = drift.length()
		p.direction = drift.normalized() if speed > 0.0 else Vector2.RIGHT
		p.initial_velocity_min = speed * 0.7
		p.initial_velocity_max = speed
		p.gravity = Vector2.ZERO
	else:
		p.position = Vector2(0.0, EMIT_OFFSET_Y)
		p.emission_rect_extents = Vector2(EMIT_HALF_WIDTH, 8.0)
		p.direction = Vector2(0, 1)
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.0
		p.gravity = drift
	p.scale_amount_min = weather.scale_min
	p.scale_amount_max = weather.scale_max
	p.angular_velocity_min = -weather.spin_degrees
	p.angular_velocity_max = weather.spin_degrees
	_apply_sprite_sheet(p, weather.h_frames)
	# Fade each particle IN then OUT over its life (multiplies the tint) so they neither
	# pop into existence nor vanish on recycle — they ease in and ease out.
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	p.emitting = true
	return p


## When [param value] flips the Weather Effects setting we rebuild from scratch: off frees
## every emitter (no CPU spent), on respawns them from the current map's weather.
func _on_setting_changed(section: StringName, property: StringName, value: Variant) -> void:
	if section != SETTING_SECTION or property != SETTING_PROPERTY:
		return
	_enabled = bool(value)
	_rebuild()


## A sprite-sheet texture (h_frames > 1) needs a CanvasItemMaterial flagged for particle
## animation; each particle then samples one frame (randomized via anim_offset) for a
## field of differently-shaped sprites. A plain texture clears the material.
func _apply_sprite_sheet(p: CPUParticles2D, h_frames: int) -> void:
	if h_frames > 1:
		var mat: CanvasItemMaterial = CanvasItemMaterial.new()
		mat.particles_animation = true
		mat.particles_anim_h_frames = h_frames
		mat.particles_anim_v_frames = 1
		mat.particles_anim_loop = false
		p.material = mat
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0 # random starting frame per particle
	else:
		p.material = null
		p.anim_offset_min = 0.0
		p.anim_offset_max = 0.0
