extends Weapon


enum State {
	READY,
	CHARGING,             ## Primary charge in progress.
	CHARGING_MULTISHOT,   ## Multishot charge in progress.
	CHARGED,              ## Reserved — not currently used; kept for future "release-on-cap" UX.
}

@export var cooldown: float = 0.8
@export var charge_time_s: float = 0.4
## Damage as a fraction of the wielder's AD. An uncharged tap deals
## min_ad_ratio × AD; a full charge deals max_ad_ratio × AD. AD = base +
## Strength + gear, so a stronger archer / better bow scales every shot.
@export var min_ad_ratio: float = 0.3  ## uncharged tap (insta-release)
@export var max_ad_ratio: float = 1.0  ## fully-charged shot
@export var min_speed: float = 400.0
@export var max_speed: float = 900.0
## Multishot fires N arrows in a cone. Per-arrow damage = primary's
## charge-scaled damage × MULTISHOT_DAMAGE_FACTOR, so a fully-charged
## multishot deals ~1.2× a single primary shot total but distributed
## across N arrows — good for crowds, weak single-target by design.
@export var multishot_cooldown: float = 1.8
@export var multishot_count: int = 3
@export var multishot_spread_deg: float = 18.0
@export var multishot_damage_factor: float = 0.4

var multishot_cooldown_until: float = 0.0

var state: State = State.READY
var charge_start: float = -1.0
var cooldown_until: float = 0.0

## bone.png sprite-sheet regions for the bow's 3 charge frames. Frame 0 =
## relaxed bow at rest, frame 1 = half-draw, frame 2 = full draw. All 16x32.
const BOW_CHARGE_FRAMES: Array[Rect2] = [
	Rect2(48, 48, 16, 32),
	Rect2(64, 48, 16, 32),
	Rect2(80, 48, 16, 32),
]
## Active tween driving the WeaponSprite region swap. Killed on each new
## phase so charge → release → re-charge doesn't leave a stale frame.
var _charge_tween: Tween


func _ready() -> void:
	super._ready()
	var now: float = Time.get_ticks_msec() / 1000.0
	cooldown_until = now + cooldown
	# Don't bother loading animation stuff on server
	if multiplayer.is_server():
		return
	if character.animation_player.has_animation_library(&"weapon"):
		return
	character.animation_player.add_animation_library(
		&"weapon",
		animation_libraries[&"weapon"]
	)


func try_perform_action(action_index: int, direction: Vector2) -> bool:
	if not can_use_weapon(action_index):
		return false
	
	perform_action(action_index, direction)

	return true


func can_use_weapon(action_index: int) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	match action_index:
		0:
			return state == State.READY and now >= cooldown_until
		1:
			# Primary release — only valid while charging the primary.
			return state == State.CHARGING or state == State.CHARGED
		2:
			# Multishot charge start — independent cooldown so the special
			# doesn't share a timer with primary tap-fire.
			return state == State.READY and now >= multishot_cooldown_until
		3:
			# Multishot release — only valid while charging multishot.
			return state == State.CHARGING_MULTISHOT
		_:
			return false


func perform_action(action_index: int, direction: Vector2) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	match action_index:
		0:
			# Primary charge start.
			state = State.CHARGING
			charge_start = now
			if GameMode.is_client():
				character.weapon_state_machine.travel(&"weapon_charge")
				_play_charge_frames()
		1:
			# Primary release. Charge ratio scales damage between min/max.
			state = State.READY
			cooldown_until = now + cooldown
			var primary_dmg: float = _charge_scaled_damage(now)
			charge_start = -1.0
			shoot_arrow(character, direction, primary_dmg)
			if GameMode.is_client():
				character.weapon_state_machine.travel(&"weapon_idle")
				_reset_charge_frame()
		2:
			# Multishot charge start — reuses the same 3-frame bow draw
			# animation so it reads identically to the primary visually.
			state = State.CHARGING_MULTISHOT
			charge_start = now
			if GameMode.is_client():
				character.weapon_state_machine.travel(&"weapon_charge")
				_play_charge_frames()
		3:
			# Multishot release. Same charge curve as primary, then each
			# arrow scaled down by multishot_damage_factor so the cone
			# isn't a single-target burst nuke.
			state = State.READY
			multishot_cooldown_until = now + multishot_cooldown
			var per_arrow_dmg: float = _charge_scaled_damage(now) * multishot_damage_factor
			charge_start = -1.0
			_fire_multishot(direction, per_arrow_dmg)
			if GameMode.is_client():
				character.weapon_state_machine.travel(&"weapon_idle")
				_reset_charge_frame()


## Charge ratio → damage. Returns min_damage at insta-release, max_damage
## at full charge_time_s held, lerps between. charge_start < 0 means we
## somehow lost the start (shouldn't happen) so default to min.
func _charge_scaled_damage(now: float) -> float:
	# Damage = AD × a charge-scaled ratio, so a stronger archer (Strength + gear)
	# hits harder at every charge level while the charge skill curve is preserved.
	var ad: float = _wielder_ad()
	if charge_start < 0.0:
		return ad * min_ad_ratio
	var held: float = now - charge_start
	var t: float = clampf(held / charge_time_s, 0.0, 1.0)
	return ad * lerpf(min_ad_ratio, max_ad_ratio, t)


func _wielder_ad() -> float:
	if character != null and character.stats_component != null:
		return character.stats_component.get_stat(Stat.AD)
	return 0.0


## NPC / auto use: fire one uncharged arrow immediately (skips the charge/release
## sequence players go through). NPC's get the uncharged base damage; that's
## fine because their HP/AD are tuned separately on the EnemyTypeResource.
func auto_attack(direction: Vector2) -> void:
	# NPC / auto use: one uncharged shot, scaled to the wielder's AD.
	shoot_arrow(character, direction, _wielder_ad() * min_ad_ratio)


func process_input(local_player: LocalPlayer) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var controller: InputComponent = local_player.controller
	# Check cooldown locally here too to avoid spamming server with requests.
	if controller.is_attack_just_pressed() and can_use_weapon(0):
		state = State.CHARGING

		Client.request_data(&"action.perform", Callable(),
		{"d": local_player.look_direction, "i": 0},
		InstanceClient.current.name
		)

		#Client.request_data(
		#	&"action.perform", Callable(),
		#	{"d": local_player.global_position.direction_to(local_player.mouse.position), "i": 0}
		#)
	elif controller.is_attack_just_released() and can_use_weapon(1):
		state = State.READY

		Client.request_data(&"action.perform", Callable(),
		{"d": local_player.look_direction, "i": 1},
		InstanceClient.current.name
		)

		#Client.request_data(
		#	&"action.perform", Callable(),
		#	{"d": local_player.global_position.direction_to(local_player.mouse.position), "i": 1}
		#)

	# Multishot — chargeable in lockstep with the primary so the player
	# uses the same press/hold/release mental model. Only the start can
	# happen from READY; release is gated on CHARGING_MULTISHOT so a
	# mid-primary-charge release of the special button doesn't fire.
	if controller.is_special_just_pressed() and can_use_weapon(2):
		state = State.CHARGING_MULTISHOT
		Client.request_data(&"action.perform", Callable(),
			{"d": local_player.look_direction, "i": 2},
			InstanceClient.current.name
		)
	elif controller.is_special_just_released() and can_use_weapon(3):
		state = State.READY
		# Predictive cooldown bump so LocalPlayer's separate input loop
		# doesn't re-send while we're waiting for the server's broadcast.
		multishot_cooldown_until = (Time.get_ticks_msec() / 1000.0) + multishot_cooldown
		Client.request_data(&"action.perform", Callable(),
			{"d": local_player.look_direction, "i": 3},
			InstanceClient.current.name
		)


## Steps the WeaponSprite through its 3 charge frames: frame 0 → 1 at half
## the charge time, 1 → 2 at full charge. Snap transitions (no Rect2 lerp —
## that produces nonsense intermediate regions). Kills any in-flight tween
## so spamming press→release leaves the bow on the correct visual frame.
func _play_charge_frames() -> void:
	if weapon_sprite == null:
		return
	if _charge_tween != null and _charge_tween.is_running():
		_charge_tween.kill()
	weapon_sprite.region_rect = BOW_CHARGE_FRAMES[0]
	_charge_tween = create_tween()
	_charge_tween.tween_interval(charge_time_s * 0.5)
	_charge_tween.tween_callback(_set_charge_frame.bind(1))
	_charge_tween.tween_interval(charge_time_s * 0.5)
	_charge_tween.tween_callback(_set_charge_frame.bind(2))


func _set_charge_frame(index: int) -> void:
	if weapon_sprite == null or index < 0 or index >= BOW_CHARGE_FRAMES.size():
		return
	weapon_sprite.region_rect = BOW_CHARGE_FRAMES[index]


func _reset_charge_frame() -> void:
	if _charge_tween != null and _charge_tween.is_running():
		_charge_tween.kill()
	if weapon_sprite != null:
		weapon_sprite.region_rect = BOW_CHARGE_FRAMES[0]


## Fires N arrows in a cone centred on [param direction]. Damage and speed
## use [member max_damage] / [member max_speed] (treats it like a fully
## charged shot per arrow — the cooldown balances against the burst).
##
## Runs on both server AND client: server arrows do damage (via the arrow's
## own server-only body_entered hook), client arrows are visual-only so the
## fan reads on every screen. arrow.gd splits server/client behaviour
## internally, same as the primary shot.
func _fire_multishot(direction: Vector2, per_arrow_damage: float) -> void:
	if multishot_count <= 0 or direction == Vector2.ZERO:
		return
	var base_angle: float = direction.angle()
	var spread_rad: float = deg_to_rad(multishot_spread_deg)
	# Evenly distribute arrows across the cone, centred on the aim line.
	# 1 arrow → just the centre. 3 arrows → -spread, 0, +spread. 5 → -2s, -s, 0, +s, +2s.
	var step: float = 0.0
	if multishot_count > 1:
		step = (spread_rad * 2.0) / float(multishot_count - 1)
	for i: int in multishot_count:
		var offset: float = -spread_rad + step * float(i) if multishot_count > 1 else 0.0
		var dir: Vector2 = Vector2.RIGHT.rotated(base_angle + offset)
		shoot_arrow(character, dir, per_arrow_damage)


func shoot_arrow(entity: Entity, direction: Vector2, arrow_damage: float = -1.0) -> void:
	var arrow: Projectile = preload("res://source/common/gameplay/items/weapons/bow/arrow.tscn").instantiate()
	arrow.top_level = true
	arrow.direction = direction
	arrow.global_position = character.right_hand_spot.global_position

	arrow.source = entity
	# Callers pass an explicit (already AD-scaled) damage value; clamp to >= 0.
	arrow.damage = maxf(0.0, arrow_damage)
	# Kept for now in case downstream code still reads .effect; not used by
	# arrow.gd anymore since damage is read directly from arrow.damage.
	arrow.effect = EffectSpec.damage(
		arrow.damage, ["Damage.Physical", "Projectile", "BasicAttack"], {"pen_tier":1}
	)

	entity.add_child(arrow)
