class_name WorldDatabase
extends Node


var database_path: String
var db: SQLite
var store: WorldStoreSqlite


func start_database(world_info: Dictionary) -> void:
	configure_database(world_info)
	open_database()
	WorldSchema.ensure_schema(db)
	store = WorldStoreSqlite.new(db)


func configure_database(world_info: Dictionary) -> void:
	var file_name := (str(world_info["name"]) + ".db").to_lower()

	# Reminder: writing to res:// is fine in editor, NOT in exports.
	if OS.has_feature("editor"):
		database_path = "res://source/server/world/data/" + file_name
	else:
		database_path = "user://db/" + file_name


func open_database() -> void:
	# Ensure directory exists for user://
	if not OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute("user://db")

	db = SQLite.new()
	db.path = database_path

	# Optional: verbosity while you develop
	# db.verbosity_level = SQLite.VerbosityLevel.NORMAL

	db.open_db()


func close_database() -> void:
	# Plugin doesn’t always expose close explicitly; if it does, call it.
	# Otherwise let refcount drop; but prefer close if available.
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close_database()


func get_player_resource(id: int) -> PlayerResource:
	return store.get_player(id)

func create_player_character(username: String, character_data: Dictionary) -> int:
	return store.create_player_character(username, character_data)

func get_account_characters(account_name: String) -> Dictionary:
	return store.get_account_characters(account_name)

func get_guild(id: int) -> Guild:
	return store.get_guild(id)

func save_player(p: PlayerResource) -> void:
	store.save_player(p)

func save_guild(g: Guild) -> void:
	store.save_guild(g)
