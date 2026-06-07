class_name JailList
## Live list of jailed ACCOUNTS. Persists to user://server_jail.cfg.
##
## Jail = the player is locked into a dedicated "jail" instance and can't
## traverse warpers out. DMs and same-instance chat still work, so they can
## still talk to friends or to other jailed players sharing the cell — handy
## for low-level infractions where a full ban is overkill.
##
## Keyed by account_name (the stable handle) so a jailed player can't escape by
## switching to another character on the same account.
##
## Enforcement (in InstanceManagerServer):
##   - On login: jailed players are routed to the jail instance, not their
##     last position.
##   - On warper traversal: blocked with a system message.
##
## Setup: create an InstanceResource with instance_name = "jail" in
## res://source/common/gameplay/maps/instance/instance_collection/.
## Until that resource exists, /jail silently no-ops on the teleport (the
## entry is still recorded, so the player gets jailed once the map is added).

const PATH: String = "user://server_jail.cfg"

static var _entries: Dictionary  # account_name (String) -> {reason, since_ms, by_id, expires_at_ms}
static var _loaded: bool


static func is_jailed(account_name: String) -> bool:
	if not _loaded:
		_load()
	var key: String = account_name.to_lower()
	if not _entries.has(key):
		return false
	var entry: Dictionary = _entries[key]
	var expires_at: int = int(entry.get("expires_at_ms", 0))
	if expires_at > 0 and int(Time.get_unix_time_from_system() * 1000.0) >= expires_at:
		_entries.erase(key)
		_save()
		return false
	return true


## Jail an account by its handle. duration_ms = 0 means until /unjail.
static func jail(account_name: String, reason: String, by_id: int, duration_ms: int = 0) -> void:
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


## Returns true if the account was jailed and is now released, false if no entry.
static func release(account_name: String) -> bool:
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
	if config.load(PATH) != OK or not config.has_section("jail"):
		return
	for key: String in config.get_section_keys("jail"):
		_entries[key] = config.get_value("jail", key, {})


static func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for account_name: String in _entries:
		config.set_value("jail", account_name, _entries[account_name])
	config.save(PATH)
