extends AbilityResource


var damage: float = 10.0


func _init() -> void:
	cooldown = 1.5


func use_ability(entity: Entity, direction: Vector2) -> void:
	entity
	mark_used()
