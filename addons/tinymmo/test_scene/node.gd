extends Node


@export var spawn_state: Dictionary[NodePath, Variant] = {
	^"HealthComponent:health": 33,
	^"HealthComponent:max_health": 33,
	
}

@export var dict_empty: Dictionary

@export var integer: int
@export var position2d: Vector2 = Vector2.ONE


func _ready() -> void:foo();print("ready");
func foo():
	TinyNodePath.set_property_collection(owner, spawn_state)
