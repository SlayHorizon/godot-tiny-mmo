extends Node
## Main Scene - This is the entry point of the application (set at application/run/main_scene).
## Its sole responsibility is to determine and initialize the application role
## (world server, gateway server, master server, or client) based on feature flags.


func _ready() -> void:
	var features: Dictionary[String, Callable] = {
		"client": start_as_client,
		"gateway-server": start_as_gateway_server,
		"master-server": start_as_master_server,
		"world-server": start_as_world_server,
	}
	
	var command_line_arg: String = CmdlineUtils.get_parsed_args().get("mode", "")
	
	if features.has(command_line_arg):
		features[command_line_arg].call()
		return
	
	for feature: String in features:
		if OS.has_feature(feature):
			features[feature].call()
			return
	
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
