class_name ChargeAbility
extends AbilityResource
## Generic hold-to-charge projectile ability: press starts the charge, release
## fires — damage and projectile speed scale with how long the button was held.
## The bow's primary shot AND its multishot are both just .tres instances of
## this (multishot = projectile_count 3 + a mana cost); a future crossbow or
## fireball staff is data, not a new weapon script.
##
## Server-authoritative: the SERVER's instance of this resource tracks
## charge_start, so held-time (and therefore damage) is computed server-side —
## a client can't lie about its charge. Clients run the same code for visuals.
##
## Cooldown stamps on RELEASE (via the weapon), mana likewise.

## The projectile scene (root must be a Projectile). No hardcoded preloads.
@export var projectile_scene: PackedScene
## Seconds of holding for a full-power shot.
@export var charge_time_s: float = 0.9
## Damage as a fraction of the wielder's AD: tap = min, full hold = max.
@export var min_ad_ratio: float = 0.3
@export var max_ad_ratio: float = 1.0
## Projectile speed also scales with charge.
@export var min_speed: float = 400.0
@export var max_speed: float = 900.0
## Number of projectiles per release (1 = single shot; 3 = a multishot cone).
@export var projectile_count: int = 1
## Half-cone in degrees for multi-projectile spreads.
@export var spread_deg: float = 18.0
## Per-projectile damage factor (multishot uses < 1.0 so the cone isn't a
## single-target burst nuke).
@export var damage_factor: float = 1.0

## Optional damage-over-time on hit (Venom Shot). 0 dps = none; dot_kind drives
## the debuff icon (&"poison", &"burn", ...).
@export var dot_dps: float = 0.0
@export var dot_duration_s: float = 0.0
@export var dot_kind: StringName = &"poison"

## True between press and release. Per-weapon-instance state (abilities are
## duplicated on equip), server-authoritative for damage.
var charging: bool = false
var _charge_start: float = -1.0


func use_ability(_entity: Entity, _direction: Vector2) -> void:
	# PRESS — begin charging. Weapon visuals (draw frames, anim) hook off
	# `charging` after this call.
	charging = true
	_charge_start = Time.get_ticks_msec() / 1000.0


func release_ability(entity: Entity, direction: Vector2) -> void:
	# RELEASE — fire, scaled by held time.
	charging = false
	var t: float = 0.0
	if _charge_start >= 0.0 and charge_time_s > 0.0:
		t = clampf(((Time.get_ticks_msec() / 1000.0) - _charge_start) / charge_time_s, 0.0, 1.0)
	_charge_start = -1.0
	if projectile_scene == null or entity == null:
		return

	var ad: float = 0.0
	if entity is Character and (entity as Character).stats_component != null:
		ad = (entity as Character).stats_component.get_stat(Stat.AD)
	var per_shot_damage: float = maxf(0.0, ad * lerpf(min_ad_ratio, max_ad_ratio, t) * damage_factor)
	var speed: float = lerpf(min_speed, max_speed, t)

	var dir_norm: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	var base_angle: float = dir_norm.angle()
	var spread_rad: float = deg_to_rad(spread_deg)
	var step: float = 0.0
	if projectile_count > 1:
		step = (spread_rad * 2.0) / float(projectile_count - 1)
	for i: int in maxi(1, projectile_count):
		var offset: float = -spread_rad + step * float(i) if projectile_count > 1 else 0.0
		_spawn(entity, Vector2.RIGHT.rotated(base_angle + offset), per_shot_damage, speed)


## Press-phase gate: can't start a new charge mid-charge; otherwise the normal
## cooldown + mana checks. (The LocalPlayer hold-to-attack loop also reads this,
## so it stays quiet while a charge is held.)
func can_use(user: Entity = null) -> bool:
	if charging:
		return false
	return super.can_use(user)


func can_use_release() -> bool:
	return charging


func predict_release() -> void:
	# Flip ONLY the flag — keep _charge_start so the server echo's
	# release_ability still computes the right charge ratio for the local
	# visual arrow (release_ability clears the timestamp itself).
	charging = false


## NPC / auto use: one full-power shot, no hold. Backdate the charge timestamp
## by a whole charge_time so release_ability computes t = 1.0.
func auto_use(entity: Entity, direction: Vector2) -> void:
	charging = true
	_charge_start = (Time.get_ticks_msec() / 1000.0) - charge_time_s
	release_ability(entity, direction)


func _init() -> void:
	has_release = true


func _spawn(entity: Entity, direction: Vector2, damage: float, speed: float) -> void:
	var projectile: Projectile = projectile_scene.instantiate()
	projectile.top_level = true
	projectile.direction = direction
	projectile.speed = speed
	projectile.source = entity
	projectile.damage = damage
	projectile.burn_dps = dot_dps
	projectile.burn_duration_s = dot_duration_s
	projectile.dot_kind = dot_kind
	if entity is Character and (entity as Character).right_hand_spot != null:
		projectile.global_position = (entity as Character).right_hand_spot.global_position
	else:
		projectile.global_position = entity.global_position
	entity.add_child(projectile)
