extends Node


@onready var world_server: Node = $WorldClient
@onready var login_scene: LoginScene = $LoginScene


func _ready() -> void:
	login_scene.world_server = world_server
