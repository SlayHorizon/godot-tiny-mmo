class_name WorldMain
extends Node


var world_info: Dictionary


func _ready() -> void:
	Engine.set_physics_ticks_per_second(20) # 60 by default
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("World Server")
	load_world_info("res://test_config/world_server_config.cfg")


func load_world_info(config_path: String) -> void:
	var parsed_arguments := CmdlineUtils.get_parsed_args()
	
	var config_file := ConfigFile.new()
	if parsed_arguments.has("config"):
		config_path = parsed_arguments["config"]
	var error := config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at %s, error: %s" % [parsed_arguments["config"], error_string(error)])
		return
	world_info = {
		"name": config_file.get_value("world-server", "name", "NoName"),
		"max_players": config_file.get_value("world-server", "max_players", 200),
		"hardcore": config_file.get_value("world-server", "hardcore", false),
		"bonus_xp": config_file.get_value("world-server", "bonus_xp", 0.0),
		"max_character": config_file.get_value("world-server", "max_character", 5),
		"pvp": config_file.get_value("world-server", "pvp", true)
	}
