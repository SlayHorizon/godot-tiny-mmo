class_name AccountResource
extends Resource


@export var id: int
@export var username: String
@export var password: String

# peer_id = O if not connected
var peer_id: int = 0


func init(_id: int, _username: String, _password: String) -> void:
	id = _id
	username = _username
	password = _password
