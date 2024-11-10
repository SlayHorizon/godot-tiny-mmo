extends Node
## Main.
## Should only care about deciding if the project is either
## a world server, gateway server, master server or a client.

func _ready() -> void:
	if OS.has_feature("client"):
		start_as_client()
	elif OS.has_feature("game-server"):
		start_as_game_server()
	elif OS.has_feature("gateway-server"):
		start_as_gateway_server()
	elif OS.has_feature("master-server"):
		start_as_master_server()


func start_as_client() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/client/client_main.tscn")


func start_as_game_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/world_server/world_main.tscn")


func start_as_gateway_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/gateway_server/gateway_main.tscn")


func start_as_master_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/master_server/master_main.tscn")
