extends Node
## Main.
## Should only care about deciding if the project is either
## a game server, gateway server or a client,
## and set basic configuration if needed.

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
	get_node("/root").add_child.call_deferred(load("res://source/client/instance_manager/instance_manger.tscn").instantiate())
	get_tree().change_scene_to_file.call_deferred("res://source/client/login_scene.tscn")


func start_as_game_server() -> void:
	Engine.set_physics_ticks_per_second(20) # 60 by default
	get_tree().change_scene_to_file.call_deferred("res://source/world_server/instance_manager/instance_manager.tscn")


func start_as_gateway_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/gateway_server/gateway_server.tscn")


func start_as_master_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/master_server/master_server.tscn")
