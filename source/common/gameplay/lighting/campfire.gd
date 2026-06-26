class_name Campfire
extends Node2D
## An animated campfire that casts a warm, flickering light — place it in dark maps (a night forest,
## a camp, a cave). Two looping AnimatedSprite2D layers (logs + flame, autoplayed) plus a PointLight2D
## whose energy wavers like a real fire.
##
## ALSO a slow REST AURA: on the SERVER it tops up HP + mana for living players lingering within
## [member heal_radius] every [member heal_interval] seconds (a fire doubles as a rest spot — refill
## between fights, save potions), popping a green "+N" per tick via the shared combat.hit heal path.
## On the CLIENT a soft green glow fades IN while the LOCAL player is resting here (in range + not full)
## and fades OUT otherwise — pure local inference, no server messages. Set BOTH per-tick amounts to 0
## for a cosmetic-only fire (the server frees it, and no glow is built).

## Soft radial reused for the heal glow (same texture the firelight uses).
const AURA_TEXTURE: Texture2D = preload("res://source/common/gameplay/lighting/light_radial.tres")
## Peak glow opacity + how fast it fades in/out (alpha per second).
const AURA_MAX_ALPHA: float = 0.22
const AURA_FADE_SPEED: float = 0.8

## Flicker: how fast the light wavers and how deep (as a fraction of the light's base energy).
@export var flicker_speed: float = 7.0
@export var flicker_amount: float = 0.18

@export_group("Rest aura")
## Living players within this radius are topped up every heal_interval seconds.
@export var heal_radius: float = 56.0
## Seconds between heal ticks. Bigger = chunkier, less-frequent green numbers (less visual noise).
@export var heal_interval: float = 2.0
## HP and mana restored per tick. The green number shows the HP gained; mana fills its bar. Both 0 =
## cosmetic-only fire.
@export var heal_hp_per_tick: float = 8.0
@export var heal_mana_per_tick: float = 8.0

@onready var _light: PointLight2D = $Light

var _phase: float
var _base_energy: float
var _heal_area: Area2D
var _aura: Sprite2D


func _ready() -> void:
	if not GameMode.is_client():
		# Headless server: no visuals. A cosmetic-only fire (no heal) frees itself like before;
		# otherwise keep just the heal zone and drop the sprite/light children.
		if not _heals():
			queue_free()
			return
		set_process(false) # the flicker + glow are client-only
		for child: Node in get_children():
			child.queue_free() # Base / Fire / Light — nothing to render headless
		_build_heal_aura()
		return
	_phase = randf() * TAU # desync multiple campfires so they don't flicker in lockstep
	_base_energy = _light.energy
	if _heals():
		_build_glow() # client heal glow, shown by local inference


func _process(delta: float) -> void:
	# Firelight flicker.
	_phase += delta * flicker_speed
	var flicker: float = sin(_phase) * 0.6 + sin(_phase * 2.3 + 1.7) * 0.4
	_light.energy = _base_energy * (1.0 + flicker * flicker_amount)
	# Heal glow: fade in while the LOCAL player is resting here, out otherwise.
	_update_glow(delta)


func _heals() -> bool:
	return heal_hp_per_tick > 0.0 or heal_mana_per_tick > 0.0


# --- Server: the heal zone ---------------------------------------------------

## Server-only: a circular zone + a repeating tick that tops up players standing in it.
func _build_heal_aura() -> void:
	_heal_area = Area2D.new()
	_heal_area.collision_layer = 0
	_heal_area.collision_mask = PhysicsLayers.CHARACTER_BODY # player + mob bodies; filtered to Player below
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = heal_radius
	shape.shape = circle
	_heal_area.add_child(shape)
	add_child(_heal_area)

	var timer: Timer = Timer.new()
	timer.wait_time = heal_interval
	timer.timeout.connect(_heal_tick)
	add_child(timer)
	timer.start()


func _heal_tick() -> void:
	if _heal_area == null:
		return
	for body: Node2D in _heal_area.get_overlapping_bodies():
		if body is Player and not (body as Player).is_dead:
			_heal_one(body as Player)


## Top up one player's HP + mana (clamped to max) and pop a green "+N" for the HP gained — reusing the
## combat.hit heal path the hammer aura uses, so everyone in the instance sees it. Mana fills its bar
## silently (there's no blue-number convention).
func _heal_one(player: Player) -> void:
	var sc: StatsComponent = player.stats_component
	var hp_gained: float = 0.0
	if heal_hp_per_tick > 0.0:
		var hp: float = sc.get_stat(Stat.HEALTH)
		var hp_max: float = sc.get_stat(Stat.HEALTH_MAX)
		if hp < hp_max:
			var new_hp: float = minf(hp_max, hp + heal_hp_per_tick)
			sc.set_stat(Stat.HEALTH, new_hp)
			hp_gained = new_hp - hp
	if heal_mana_per_tick > 0.0:
		var mana: float = sc.get_stat(Stat.MANA)
		var mana_max: float = sc.get_stat(Stat.MANA_MAX)
		if mana < mana_max:
			sc.set_stat(Stat.MANA, minf(mana_max, mana + heal_mana_per_tick))

	if hp_gained < 1.0 or WorldServer.curr == null:
		return
	var map: Node = player.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"combat.hit", {
			"amount": int(round(hp_gained)),
			"position": player.global_position,
			"heal": true,
		}),
		map.get_parent().name
	)


# --- Client: the heal glow ---------------------------------------------------

## Client-only: a soft green disc under the fire, invisible until the local player is being healed here.
func _build_glow() -> void:
	_aura = Sprite2D.new()
	_aura.texture = AURA_TEXTURE
	_aura.modulate = Color(0.45, 1.0, 0.6, 0.0) # green, transparent until needed
	var tex_w: int = AURA_TEXTURE.get_width()
	if tex_w > 0:
		_aura.scale = Vector2.ONE * (heal_radius * 2.0 / float(tex_w))
	add_child(_aura)
	move_child(_aura, 0) # draw under the fire sprites (still above the ground)


## Fade the glow toward visible while the LOCAL player rests here (in range + not full HP/mana).
func _update_glow(delta: float) -> void:
	if _aura == null:
		return
	var target: float = 0.0
	var lp: Character = null
	if is_instance_valid(ClientState):
		lp = ClientState.local_player
	if lp != null and not lp.is_dead \
			and global_position.distance_to(lp.global_position) <= heal_radius:
		var sc: StatsComponent = lp.stats_component
		if sc.get_stat(Stat.HEALTH) < sc.get_stat(Stat.HEALTH_MAX) \
				or sc.get_stat(Stat.MANA) < sc.get_stat(Stat.MANA_MAX):
			target = AURA_MAX_ALPHA
	_aura.modulate.a = move_toward(_aura.modulate.a, target, delta * AURA_FADE_SPEED)
