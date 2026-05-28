class_name Logger
## Structured server log. Lines look like:
##   [2026-05-28 14:32:01 UTC] [INFO] Periodic save: 4 player(s) flushed, backup ok.
##
## Each day rolls into a new file at user://logs/server_YYYY-MM-DD.log so the
## history doesn't grow into one giant file. Also echoes to stdout (so the
## existing server console output is unchanged) and forwards warn/error through
## Godot's push_warning / push_error for editor-time visibility.
##
## Usage:
##   Logger.info("Peer %d authenticated as %s." % [peer_id, name])
##   Logger.warn("Player without resource: %d" % peer_id)
##   Logger.error("Database open failed at %s" % path)
##
## All methods are static; the file handle is held in a static var and rotated
## on day-change.

const DIR: String = "user://logs"

static var _file: FileAccess
static var _current_day: String = ""


static func info(msg: String) -> void:
	_write("INFO", msg)


static func warn(msg: String) -> void:
	_write("WARN", msg)
	push_warning(msg)


static func error(msg: String) -> void:
	_write("ERROR", msg)
	push_error(msg)


# --- internals ---

static func _write(level: String, msg: String) -> void:
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	var day: String = "%04d-%02d-%02d" % [int(now.year), int(now.month), int(now.day)]
	if day != _current_day or _file == null:
		_rotate(day)
	var ts: String = "%s %02d:%02d:%02d UTC" % [day, int(now.hour), int(now.minute), int(now.second)]
	var line: String = "[%s] [%s] %s" % [ts, level, msg]
	print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush() # Make sure crashes don't lose the most recent lines.


static func _rotate(day: String) -> void:
	if _file != null:
		_file.close()
		_file = null
	DirAccess.make_dir_recursive_absolute(DIR)
	var path: String = "%s/server_%s.log" % [DIR, day]
	# WRITE_READ opens for append if the file exists (seek_end below).
	_file = FileAccess.open(path, FileAccess.READ_WRITE)
	if _file == null:
		# File didn't exist yet; create it.
		_file = FileAccess.open(path, FileAccess.WRITE_READ)
	if _file != null:
		_file.seek_end()
	_current_day = day
