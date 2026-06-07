class_name MeleeSwingAbility
extends AbilityResource
## Generic "swing a melee weapon" ability. Owns the hitbox spawn, damage
## resolution, and animation hook. The ability lives in combat/ — any
## melee weapon (sword, axe, dagger, future hammer) references it from its
## item.tres without re-implementing the swing.
##
## Per-weapon tuning happens via the @export fields below: a heavy axe might
## bump base_damage and spawn_offset; a dagger might shrink both.


## Spawned in front of [param user] when the swing fires.
@export var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/melee_arc.tscn")
## Base damage floor. Effective damage = max(base_damage, attacker's AD).
@export var base_damage: float = 12.0
## How far forward (along [param direction]) the hitbox spawns from the
## character's origin. The CollisionShape inside the arc scene already has
## its own forward offset + radius — this just biases the whole spawn so
## tuning reach is one number instead of two. Keep small (0–8) for most
## weapons; bump higher for polearms / spears.
@export var spawn_offset: float = 0.0
## Animation to play when the swing fires. Library prefix included
## (e.g. "weapon/sword.swing"). The weapon scene loads the library on equip.
@export var swing_animation: StringName


func use_ability(user: Entity, direction: Vector2) -> void:
	# Animation runs on every peer (client AND server) so the swing reads
	# visually on every screen. Character.play_action_animation is a no-op
	# on the headless server, so we can call it unconditionally.
	if user is Character:
		(user as Character).play_action_animation(swing_animation)

	# Hitbox + damage are server-authoritative. Clients trust the server's
	# combat.hit broadcast for damage feedback (numbers, future flash/sound).
	# GameMode is static so it works inside Resources (which don't have a
	# multiplayer property of their own).
	if not GameMode.is_world_server():
		return

	if arc_scene == null or user == null:
		return
	var arc: MeleeArc = arc_scene.instantiate()
	arc.source = user if user is Character else null
	# Damage scales with the wielder's AD (STRENGTH attribute + gear); base_damage
	# is just the floor for a weapon with no attack power behind it.
	var ad: float = (user as Character).stats_component.get_stat(Stat.AD) if user is Character else 0.0
	arc.damage = maxf(base_damage, ad)
	var dir_norm: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	arc.global_position = user.global_position + dir_norm * spawn_offset
	arc.rotation = dir_norm.angle()
	user.get_parent().add_child(arc)
