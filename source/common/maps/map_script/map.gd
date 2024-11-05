@icon("res://assets/node_icons/color/icon_map_colored.png")
class_name Map
extends Node2D


var warpers: Dictionary#[int, Warper]


func _ready() -> void:
	for children in get_children():
		if children is Warper:
			var warper_id: int = (children as Warper).warper_id
			warpers[warper_id] = children


func get_spawn_position(warper_id: int = 0) -> Vector2:
	if warpers.has(warper_id):
		return (warpers[warper_id] as Warper).global_position
	return Vector2.ZERO
