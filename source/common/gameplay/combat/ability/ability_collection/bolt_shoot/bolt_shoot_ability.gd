class_name BoltShootAbility
extends AbilityResource
## Generic "fire a magic bolt" ability — the caster counterpart of MeleeSwingAbility.
## Spawns a projectile whose damage scales off the wielder's AP (Ability Power),
## the magic mirror of AD: base AP is 0, so the weapon itself grants AP via a
## StatModifier (and the Intelligence attribute feeds it once magic unlocks).
##
## Cooldown-gated (no mana cost yet — the mana pool is still a placeholder; wire a
## cost here when that system ships). Spawns on every peer like arrows: the server
## bolt deals damage (CombatHit), client bolts are the visual.

## The bolt scene (root must be a Projectile).
@export var projectile_scene: PackedScene
## Damage as a fraction of the wielder's AP. 1.0 = a bolt hits for 100% AP.
@export var ap_ratio: float = 1.0
@export var speed: float = 500.0
## Optional cast animation ("weapon/...'"). Empty = none.
@export var cast_animation: StringName

## Optional burn applied on hit (DamageOverTime, refreshed not stacked).
## 0 = plain bolt. Damage ticks 1/s for the duration.
@export var burn_dps: float = 0.0
@export var burn_duration_s: float = 0.0

## Piercing: the bolt passes through up to [member pierce_count] targets before
## stopping (Overload). Default = a normal one-and-done bolt.
@export var piercing: bool = false
@export var pierce_count: int = 0

## Bolt tint — the ONE visual knob, so new bolt flavors are pure data (the
## bolt scenes' sprites are white on purpose). Default = the classic arcane
## purple; heal sets green, ember sets red.
@export var bolt_modulate: Color = Color(0.75, 0.55, 1.0)

## Caps the bolt's reach in PIXELS (0 = use the projectile's own default lifetime). A
## melee caster (the book) sets a short range so its bolt doesn't out-poke the bow.
@export var max_range: float = 0.0

## Aim spread in DEGREES — the shot leaves at a random angle within ±this of your aim, so a
## rapid-fire spray (the Arc Strike minigun) throws a cone instead of a laser: reliable
## point-blank, loose at range. 0 = pinpoint. The SERVER bakes the sprayed angle into the
## action echo (see Weapon.aim_with_spread) so every peer's visual bolt matches the one
## that actually hit.
@export var spread_degrees: float = 0.0

## Client-only juice: [member muzzle_vfx] sparks at the hand on each shot, [member impact_vfx]
## sparks where the bolt lands (a DAMAGED hit). Null = none. One SpriteFrames can serve both.
@export var muzzle_vfx: SpriteFrames
@export var impact_vfx: SpriteFrames

## > 0 makes the bolt EXPLODE where it stops (hit OR wall): an AoE burst of
## [member explode_ap_ratio] × AP magic damage to everything in the radius (the Fireball).
## The direct-hit target takes the bolt's own damage too. Explosion visual = impact_vfx.
@export var explode_radius: float = 0.0
@export var explode_ap_ratio: float = 0.0


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is Character:
		(user as Character).play_action_animation(cast_animation)
	# Muzzle spark at the hand (client visual, rides right_hand_spot so it tracks aim) — each
	# shot visibly fires from you.
	if GameMode.is_client() and muzzle_vfx != null and user is Character \
			and (user as Character).right_hand_spot != null:
		SpriteEffect.spawn((user as Character).right_hand_spot, muzzle_vfx, {
			"scale": Vector2(0.3, 0.3),
			"z_index": 1,
			"speed_scale": 1.8,  # snappy, so a 4/s spray doesn't pile up sparks
		})
	if projectile_scene == null or user == null:
		return
	var bolt: Projectile = projectile_scene.instantiate()
	bolt.top_level = true
	bolt.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	bolt.speed = speed
	if max_range > 0.0:
		bolt.lifetime = max_range / maxf(1.0, speed)  # reach ≈ max_range px
	bolt.source = user
	bolt.damage = maxf(0.0, _wielder_ap(user) * ap_ratio)
	bolt.damage_type = CombatHit.DAMAGE_MAGIC # mitigated by MR, not armor
	bolt.burn_dps = burn_dps
	bolt.burn_duration_s = burn_duration_s
	bolt.piercing = piercing
	bolt.pierce_left = pierce_count
	bolt.modulate = bolt_modulate
	bolt.impact_vfx = impact_vfx
	bolt.explode_radius = explode_radius
	bolt.explode_damage = maxf(0.0, _wielder_ap(user) * explode_ap_ratio)
	bolt.global_position = _spawn_position(user)
	user.add_child(bolt)


func _wielder_ap(user: Entity) -> float:
	if user is Character and (user as Character).stats_component != null:
		return (user as Character).stats_component.get_stat(Stat.AP)
	return 0.0


func _spawn_position(user: Entity) -> Vector2:
	if user is Character and (user as Character).right_hand_spot != null:
		return (user as Character).right_hand_spot.global_position
	return user.global_position
