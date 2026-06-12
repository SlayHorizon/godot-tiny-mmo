class_name HealBoltAbility
extends BoltShootAbility
## Support twin of BoltShootAbility: fires a bolt that HEALS the first ally it
## hits instead of damaging enemies (see HealBolt for the ally rules). Heal
## amount = AP × ap_ratio. The game's first support tool — a 2v2 with a healer
## plays like a different game.


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is Character:
		(user as Character).play_action_animation(cast_animation)
	if projectile_scene == null or user == null:
		return
	var bolt: HealBolt = projectile_scene.instantiate()
	bolt.top_level = true
	bolt.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	bolt.speed = speed
	bolt.source = user
	bolt.heal_amount = maxf(0.0, _wielder_ap(user) * ap_ratio)
	bolt.modulate = bolt_modulate
	bolt.global_position = _spawn_position(user)
	user.add_child(bolt)
