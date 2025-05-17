class_name AbilityResource
extends Resource


@export var name: String
@export var cooldown: float = 1.0


var last_action_time: float = -INF


# Called when the ability is used
func use_ability(owner: Node2D, direction: Vector2) -> void:
	pass


func can_use() -> bool:
	return (Time.get_ticks_msec() / 1000.0) - last_action_time >= cooldown


func mark_used():
	last_action_time = Time.get_ticks_msec() / 1000.0
