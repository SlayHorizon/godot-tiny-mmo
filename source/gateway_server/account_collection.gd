class_name AccountResourceCollection
extends Resource


@export var collection: Dictionary = {}

@export var next_account_id: int = 0:
	get = _get_next_account_id
@export var next_player_id: int = 0:
	get = _get_next_player_id


func _get_next_account_id() -> int:
	next_account_id += 1
	return next_account_id


func _get_next_player_id() -> int:
	next_player_id += 1
	return next_player_id
