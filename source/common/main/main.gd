extends Node
## Main. 
## Should only care about deciding if the project is either a server or a client,
## and set basic things.

func _ready() -> void:
	if OS.has_feature("client"):
		setup_client()
	elif OS.has_feature("server"):
		setup_server()


func setup_client() -> void:
	get_node("/root").add_child.call_deferred(load("res://source/client/ui/ui.tscn").instantiate())
	get_tree().change_scene_to_file.call_deferred("res://source/client/instance_manager/instance_manger.tscn")

func setup_server() -> void:
	Engine.set_physics_ticks_per_second(20) # 60 by default
	DisplayServer.window_set_title("Server")
	get_window().position = Vector2(0, 0) # Used for faster debugging
	get_tree().change_scene_to_file.call_deferred("res://source/server/instance_manager/instance_manager.tscn")
