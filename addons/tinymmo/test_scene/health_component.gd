extends Node


@export var health: int = 10
@export var max_heatlh: int = 10

func foo() -> void:
	print("Health: ", health, " | MaxHealth: ", max_heatlh)
