class_name WorldDatabase
extends Node


var database_path: String

var player_data: WorldPlayerData


func start_database(world_info: Dictionary) -> void:
	configure_database(world_info)
	load_world_database()


func configure_database(world_info: Dictionary) -> void:
	if OS.has_feature("editor"):
		database_path = "res://source/worlddata/"
	else:
		database_path = "."
	database_path += str(world_info["name"] + ".tres").to_lower()
	

func load_world_database() -> void:
	if ResourceLoader.exists(database_path, "WorldPlayerData"):
		player_data = ResourceLoader.load(database_path, "WorldPlayerData")
	else:
		player_data = WorldPlayerData.new()


func save_world_database() -> void:
	var error: Error = ResourceSaver.save(player_data, database_path)
	if error:
		printerr("Error while saving player_data %s." % error_string(error))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_world_database()
