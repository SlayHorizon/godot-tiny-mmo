extends AbilityResource


var damage: float = 2.0


func _init() -> void:
	cooldown = 1.5


func use_ability(entity: Entity, direction: Vector2) -> void:
	var arrow: Projectile = preload("res://source/common/items/weapons/bow/arrow.tscn").instantiate()
	arrow.top_level = true
	arrow.direction = direction
	arrow.global_position = entity.global_position
	arrow.attack = Attack.new(entity, damage)
	entity.add_child(arrow)
