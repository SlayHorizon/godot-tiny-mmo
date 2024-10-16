class_name AccountResource
extends Resource


@export var id: int
@export var username: String
@export var password: String
@export var player_collection: Array[PlayerResource] = []


func _init(_id: int, _username: String, _password: String) -> void:
	id = _id
	username = _username
	password = _password
