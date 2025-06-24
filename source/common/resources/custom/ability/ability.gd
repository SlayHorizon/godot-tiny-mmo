class_name AbilityResource
extends Resource


@export var name: String
@export var cooldown: float = 1.0


var last_action_time: float = -INF


func use_ability(_entity: Entity, _direction: Vector2) -> void:
	pass
#func use_ability(_entity: Entity, _payload: Dictionary) -> void:

func can_use() -> bool:
	return (Time.get_ticks_msec() / 1000.0) - last_action_time >= cooldown


func mark_used():
	last_action_time = Time.get_ticks_msec() / 1000.0
