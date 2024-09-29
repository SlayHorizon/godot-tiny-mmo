class_name CredentialsResource
extends Resource

static var last_id: int

@export var id: int
@export var username: String
@export var password: String

func _init(_id: int, _username: String, _password: String) -> void:
	id = _id
	username = _username
	password = _password