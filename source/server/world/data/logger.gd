class_name ServerLog
## Structured server log. Lines look like:
##   [2026-05-28 14:32:01 UTC] [INFO] Periodic save: 4 player(s) flushed, backup ok.
##
## Each day rolls into a new file at user://logs/server_YYYY-MM-DD.log so the
## history doesn't grow into one giant file. Also echoes to stdout (so the
## existing server console output is unchanged) and forwards warn/error through
## Godot's push_warning / push_error for editor-time visibility.
##
## Named ServerLog because Godot 4 already exposes a `Logger` builtin.
##
## Usage:
##   ServerLog.info("Peer %d authenticated as %s." % [peer_id, name])
##   ServerLog.warn("Player without resource: %d" % peer_id)
##   ServerLog.error("Database open failed at %s" % path)
##
## All methods are static; the file handle is held in a static var and rotated
## on day-change.

const DIR: String = "user://logs"
## In-memory ring buffer so the dashboard can fetch the recent tail without
## reopening a file on every poll.
const RECENT_MAX: int = 500

static var _file: FileAccess
static var _current_day: String = ""
static var _recent: PackedStringArray = []


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
	_recent.append(line)
	if _recent.size() > RECENT_MAX:
		_recent.remove_at(0)
	if _file != null:
		_file.store_line(line)
		_file.flush() # Make sure crashes don't lose the most recent lines.


## Returns the last [param n] lines from the in-memory ring. Cheap — used by
## the dashboard's /v1/logs poll and by the heartbeat snapshot.
static func recent(n: int = 200) -> PackedStringArray:
	if n <= 0 or _recent.is_empty():
		return PackedStringArray()
	var start: int = maxi(0, _recent.size() - n)
	return _recent.slice(start)


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
