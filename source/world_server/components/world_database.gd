class_name WorldDatabase
extends Node


#var data_folder_path: String = "user://data_server/"
var player_data_file_path: String = "res://source/world_server/data/player_data.tres"

var player_data: WorldPlayerDataResource


func _ready() -> void:
	#tree_exiting.connect(self._on_tree_exiting)
	load_world_database()


func load_world_database() -> void:
	if ResourceLoader.exists(player_data_file_path, "WorldPlayerDataResource"):
		player_data = ResourceLoader.load(player_data_file_path, "WorldPlayerDataResource")
	else:
		player_data = WorldPlayerDataResource.new()


func save_world_database() -> void:
	var error := ResourceSaver.save(player_data, player_data_file_path)
	if error:
		printerr("Error while saving player_data %s." % error_string(error))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_world_database()
