class_name AccountResourceCollection
extends Resource


@export var collection: Dictionary = {}

@export var next_account_id: int = 0
#@export var next_player_id: int = 0


func get_new_account_id() -> int:
	var new_account_id: int = next_account_id
	next_account_id += 1
	return new_account_id
