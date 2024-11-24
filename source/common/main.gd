extends Node
## Main Scene - This is the entry point of the application (set at application/run/main_scene).
## Its sole responsibility is to determine and initialize the application role
## (world server, gateway server, master server, or client) based on feature flags.


func _ready() -> void:
	if OS.has_feature("client"):
		start_as_client()
	elif OS.has_feature("gateway-server"):
		start_as_gateway_server()
	elif OS.has_feature("master-server"):
		start_as_master_server()
	elif OS.has_feature("world-server"):
		start_as_world_server()
	else:
		printerr(
			"No valid feature tag was found."
			+ "\nPlease check either README.md or common/main.gd."
		)


func start_as_client() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/client/client_main.tscn")


func start_as_gateway_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/gateway_server/gateway_main.tscn")


func start_as_master_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/master_server/master_main.tscn")


func start_as_world_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://source/world_server/world_main.tscn")
