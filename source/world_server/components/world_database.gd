class_name WorldDatabase
extends Node


@export var main: WorldMain

var database_path: String

var player_data: WorldPlayerData


func _ready() -> void:
	if not main.is_ready:
		await main.configuration_finished
	
	if OS.has_feature("editor"):
		database_path = "res://source/world_server/data/"
	else:
		database_path = "."
	database_path += str(main.world_info["name"] + ".tres").to_lower()
	
	load_world_database()


func load_world_database() -> void:
	if ResourceLoader.exists(database_path, "WorldPlayerData"):
		player_data = ResourceLoader.load(database_path, "WorldPlayerData")
	else:
		player_data = WorldPlayerData.new()


func save_world_database() -> void:
	var error := ResourceSaver.save(player_data, database_path)
	if error:
		printerr("Error while saving player_data %s." % error_string(error))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_world_database()
