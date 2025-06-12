extends Node

@export var dict:Dictionary = {}
@export var dict2: Dictionary[NodePath, Variant] = {
	^"HealthComponent:health": 33,
	^"HealthComponent:max_health": 33,
	
}

@export var dict_empty: Dictionary

@export var salade: int

func _ready() -> void:foo();print("ready");
func foo():
	TinyNodePath.set_property_collection(owner, dict2)
