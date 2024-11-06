extends Node


@onready var world_manager: WorldManagerClient = $WorldManagerClient
@onready var world_server: WorldServer = $WorldServer


func _ready() -> void:
	world_manager.world_server = world_server
	world_manager.token_received.connect(
		func(token: String, account_id: int):
			world_server.token_list[token] = account_id
	)
