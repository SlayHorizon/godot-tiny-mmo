class_name MuteList
## Live list of chat-muted player ids. Persists to user://server_mutes.cfg so
## mutes survive a server restart, but does NOT touch player DB rows — the
## config file is the single source of truth, easy to audit / hand-edit, and
## independent from character data (works on offline players too).
##
## Supports timed mutes via expires_at_ms (0 = permanent). Expired mutes are
## lazily removed when is_muted() is queried, so there's no background scan.

const PATH: String = "user://server_mutes.cfg"

static var _entries: Dictionary  # player_id (int) -> {reason, since_ms, by_id}
static var _loaded: bool


static func is_muted(player_id: int) -> bool:
	if not _loaded:
		_load()
	if not _entries.has(player_id):
		return false
	var entry: Dictionary = _entries[player_id]
	var expires_at: int = int(entry.get("expires_at_ms", 0))
	# 0 = permanent. Otherwise auto-expire on read so admins don't have to
	# manually unmute.
	if expires_at > 0 and int(Time.get_unix_time_from_system() * 1000.0) >= expires_at:
		_entries.erase(player_id)
		_save()
		return false
	return true


## Mute a player by their permanent player_id. by_id = the moderator's player_id,
## stored for audit. duration_ms = 0 means permanent (until /unmute). Persists
## immediately.
static func mute(player_id: int, reason: String, by_id: int, duration_ms: int = 0) -> void:
	if not _loaded:
		_load()
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_entries[player_id] = {
		"reason": reason,
		"since_ms": now_ms,
		"by_id": by_id,
		"expires_at_ms": 0 if duration_ms <= 0 else now_ms + duration_ms,
	}
	_save()


## Returns true if the player was muted and is now unmuted, false if no entry.
static func unmute(player_id: int) -> bool:
	if not _loaded:
		_load()
	if not _entries.has(player_id):
		return false
	_entries.erase(player_id)
	_save()
	return true


static func entries() -> Dictionary:
	if not _loaded:
		_load()
	return _entries.duplicate()


static func _load() -> void:
	_loaded = true
	var config: ConfigFile = ConfigFile.new()
	if not FileAccess.file_exists(PATH):
		return
	if config.load(PATH) != OK or not config.has_section("mutes"):
		return
	# ConfigFile keys are strings; player ids are ints — convert at the boundary.
	for key: String in config.get_section_keys("mutes"):
		var entry: Dictionary = config.get_value("mutes", key, {})
		_entries[int(key)] = entry


static func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for player_id: int in _entries:
		config.set_value("mutes", str(player_id), _entries[player_id])
	config.save(PATH)
