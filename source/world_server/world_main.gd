class_name WorldMain
extends Node


var world_config_file: ConfigFile

var world_info: Dictionary


func _ready() -> void:
	# Server tick rate
	# For comparaison:
	# Eve Online - 1 tick par second.
	# Fortnite (Battle royale 100 players) - 30 ticks per second.
	# Albion Online - 2 ticks per second (to verify).
	# Valorant (5v5 FPS game) - 128 ticks per second.
	# I believe it depends of your game and architecture, it's a large topic.
	Engine.set_physics_ticks_per_second(10) # 60 by default
	
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("World Server")
	
	# Default config path. to use another one, override this;
	# or write --config=config_file_path.cfg as a launch argument.
	var error: bool = load_world_config("res://data/config/world_server_config.cfg")
	if error:
		printerr("World server loading configuration failed.")
	else:
		$Database.start_database(world_info)
		$WorldManagerClient.start_client_to_master_server(world_info)
		$WorldServer.start_world_server()


func load_world_config(config_path: String) -> bool:
	var config_file := ConfigFile.new()
	var parsed_arguments: Dictionary = CmdlineUtils.get_parsed_args()
	
	if parsed_arguments.has("config"):
		config_path = parsed_arguments["config"]
	
	var error: Error = config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at \"%s\".\nError: %s" % [config_path, error_string(error)])
		return true
	
	world_info = {
		"name": config_file.get_value("world-server", "name", "NoName"),
		"max_players": config_file.get_value("world-server", "max_players", 200),
		"hardcore": config_file.get_value("world-server", "hardcore", false),
		"motd": config_file.get_value("world-server", "motd", "Welcome!"),
		"bonus_xp": config_file.get_value("world-server", "bonus_xp", 0.0),
		"max_character": config_file.get_value("world-server", "max_character", 5),
		"pvp": config_file.get_value("world-server", "pvp", true)
	}
	
	world_config_file = config_file
	return false
