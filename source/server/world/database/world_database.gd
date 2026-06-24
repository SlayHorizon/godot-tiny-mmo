class_name WorldDatabase
extends Node


var database_path: String
var db: SQLite
var store: WorldStoreSqlite
var mail_store: MailStore


func start_database(world_info: Dictionary) -> void:
	configure_database(world_info)
	open_database()
	WorldSchema.ensure_schema(db)
	store = WorldStoreSqlite.new(db)
	mail_store = MailStore.new(db)


func configure_database(world_info: Dictionary) -> void:
	var file_name: String = (str(world_info["name"]) + ".db").to_lower()

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
	# Durability + concurrency. WAL lets the live backup byte-copy run alongside
	# writes without tearing (backup_database assumes this) and survives a crash
	# mid-write; NORMAL is the standard safe+fast sync level under WAL. PRAGMAs are
	# connection settings, not schema — no migration / wipe.
	db.query("PRAGMA journal_mode=WAL;")
	db.query("PRAGMA synchronous=NORMAL;")


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


## Flush every still-connected player to disk. Called from the periodic save
## tick AND from the console's `save` / `shutdown` commands — previously the
## console called a method that didn't exist, so shutdowns silently lost
## anyone who hadn't disconnected yet. Returns the count actually saved.
func save_all_connected(connected_players: Dictionary) -> int:
	var count: int = 0
	for peer_id: int in connected_players:
		var p: PlayerResource = connected_players[peer_id]
		if p == null:
			continue
		store.save_player(p)
		count += 1
	return count


## Snapshot the live .db file to user://db_backups/<name>_<unix_ts>.db and
## prune older backups to keep at most [param keep_last]. Cheap byte-copy —
## SQLite WAL keeps the live file consistent enough that a crash mid-write
## still leaves a recoverable backup file. Returns true on success.
func backup_database(keep_last: int = 10) -> bool:
	if database_path.is_empty():
		return false
	if not FileAccess.file_exists(database_path):
		return false

	var backup_dir: String = "user://db_backups"
	DirAccess.make_dir_recursive_absolute(backup_dir)

	var base_name: String = database_path.get_file()
	var name_without_ext: String = base_name.get_basename()
	var unix_ts: int = int(Time.get_unix_time_from_system())
	var backup_path: String = "%s/%s_%d.db" % [backup_dir, name_without_ext, unix_ts]

	var src: FileAccess = FileAccess.open(database_path, FileAccess.READ)
	if src == null:
		return false
	var contents: PackedByteArray = src.get_buffer(src.get_length())
	src.close()

	var dst: FileAccess = FileAccess.open(backup_path, FileAccess.WRITE)
	if dst == null:
		return false
	dst.store_buffer(contents)
	dst.close()

	_rotate_backups(backup_dir, name_without_ext, keep_last)
	return true


func _rotate_backups(backup_dir: String, name_prefix: String, keep_last: int) -> void:
	var dir: DirAccess = DirAccess.open(backup_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var backups: Array[String] = []
	var file: String = dir.get_next()
	while not file.is_empty():
		if not dir.current_is_dir() and file.begins_with(name_prefix + "_") and file.ends_with(".db"):
			backups.append(file)
		file = dir.get_next()
	dir.list_dir_end()
	# Filenames embed the unix timestamp, so lexical sort matches chronological.
	backups.sort()
	while backups.size() > keep_last:
		var to_remove: String = backups.pop_front()
		DirAccess.remove_absolute(backup_dir + "/" + to_remove)
