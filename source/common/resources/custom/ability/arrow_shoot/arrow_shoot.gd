extends AbilityResource


func _init() -> void:
	cooldown = 2.0


func use_ability(owner: Node2D, direction: Vector2) -> void:
	var arrow: Area2D = preload("res://source/common/items/weapons/bow/arrow.tscn").instantiate()
	arrow.top_level = true
	arrow.direction = direction
	arrow.global_position = owner.global_position
	owner.add_child(arrow)
