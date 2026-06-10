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


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is Character:
		(user as Character).play_action_animation(cast_animation)
	if projectile_scene == null or user == null:
		return
	var bolt: Projectile = projectile_scene.instantiate()
	bolt.top_level = true
	bolt.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	bolt.speed = speed
	bolt.source = user
	bolt.damage = maxf(0.0, _wielder_ap(user) * ap_ratio)
	bolt.damage_type = CombatHit.DAMAGE_MAGIC # mitigated by MR, not armor
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
