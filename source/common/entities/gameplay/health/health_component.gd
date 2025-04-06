extends Node
class_name HealthComponent


var health: float
var max_health: float


func _init(_health: float, _max_health: float) -> void:
	health = _health
	max_health = _max_health


func apply_attack(attack: Attack) -> void:
	health -= attack.damage
