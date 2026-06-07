class_name MuteList
## Live list of chat-muted ACCOUNTS. Persists to user://server_mutes.cfg so mutes
## survive a server restart, but does NOT touch player DB rows — the config file
## is the single source of truth, easy to audit / hand-edit, and independent from
## character data (works on offline accounts too).
##
## Keyed by account_name (the stable handle), so a muted player can't dodge it by
## switching to another character on the same account. Supports timed mutes via
## expires_at_ms (0 = permanent). Expired mutes are lazily removed when is_muted()
## is queried, so there's no background scan.

const PATH: String = "user://server_mutes.cfg"

static var _entries: Dictionary  # account_name (String) -> {reason, since_ms, by_id, expires_at_ms}
static var _loaded: bool


static func is_muted(account_name: String) -> bool:
	if not _loaded:
		_load()
	var key: String = account_name.to_lower()
	if not _entries.has(key):
		return false
	var entry: Dictionary = _entries[key]
	var expires_at: int = int(entry.get("expires_at_ms", 0))
	# 0 = permanent. Otherwise auto-expire on read so admins don't have to
	# manually unmute.
	if expires_at > 0 and int(Time.get_unix_time_from_system() * 1000.0) >= expires_at:
		_entries.erase(key)
		_save()
		return false
	return true


## Mute an account by its handle. by_id = the moderator's player_id, stored for
## audit. duration_ms = 0 means permanent (until /unmute). Persists immediately.
static func mute(account_name: String, reason: String, by_id: int, duration_ms: int = 0) -> void:
	if not _loaded:
		_load()
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_entries[account_name.to_lower()] = {
		"reason": reason,
		"since_ms": now_ms,
		"by_id": by_id,
		"expires_at_ms": 0 if duration_ms <= 0 else now_ms + duration_ms,
	}
	_save()


## Returns true if the account was muted and is now unmuted, false if no entry.
static func unmute(account_name: String) -> bool:
	if not _loaded:
		_load()
	var key: String = account_name.to_lower()
	if not _entries.has(key):
		return false
	_entries.erase(key)
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
	for key: String in config.get_section_keys("mutes"):
		_entries[key] = config.get_value("mutes", key, {})


static func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for account_name: String in _entries:
		config.set_value("mutes", account_name, _entries[account_name])
	config.save(PATH)
