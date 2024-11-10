extends Node


# Loading classes 
const Database = preload("res://source/world_server/resources/world_database_resource.gd")

#var data_folder_path: String = "user://data_server/"
var database_file_path: String = "../world_database_resource.tres"
var database: Database


func _ready() -> void:
	tree_exiting.connect(self._on_tree_exiting)
	load_world_database()


func load_world_database() -> void:
	if ResourceLoader.exists(database_file_path):
		database = ResourceLoader.load(database_file_path)
	else:
		database = Database.new()


func save_world_database() -> void:
	var error := ResourceSaver.save(database, database_file_path)
	if error:
		printerr("Error while saving database %s." % error_string(error))


func get_account_data(account_id: int) -> Dictionary:
	var data := {}
	if database.accounts.has(account_id):
		for player_id: int in database.accounts[account_id]:
			var player_character: PlayerResource = database.players[player_id]
			data[player_id] = {
				"name": player_character.display_name,
				"class": player_character.character_class,
				"level": player_character.level
			}
	return data


func get_player_resource(player_id: int) -> PlayerResource:
	if database.players.has(player_id):
		return database.players[player_id]
	return PlayerResource.new(player_id)


func _on_tree_exiting() -> void:
	save_world_database()
