extends AbilityResource


var damage: float = 10.0


func _init() -> void:
	cooldown = 1.5


func use_ability(entity: Entity, direction: Vector2) -> void:
	mark_used()

	var arrow: Projectile = preload("res://source/common/gameplay/items/weapons/bow/arrow.tscn").instantiate()
	arrow.top_level = true
	arrow.direction = direction
	arrow.global_position = entity.global_position
	
	arrow.source = entity
	arrow.effect = EffectSpec.damage(
		damage, ["Damage.Physical", "Projectile", "BasicAttack"], {"pen_tier":1}
	)
	
	entity.add_child(arrow)
