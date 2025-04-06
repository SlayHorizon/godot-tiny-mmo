extends Entity


@export var health_component: HealthComponent


func _ready() -> void:
	health_component.apply_attack
