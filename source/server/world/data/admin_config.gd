class_name AdminConfig
## Maps account names to a server role, granted LIVE (read on each permission check, not
## written to the DB). Lets the server owner grant admin by editing a config file — no DB
## edits, no debug-only hacks — and removing an account revokes it immediately.
##
## Looks for "user://server_admins.cfg" first (editable next to a deployed build), then the
## bundled "res://data/config/server_admins.cfg". Format (role names come from ServerRoles):
##   [admins]
##   MyAccount="senior_admin"

const USER_PATH: String = "user://server_admins.cfg"
const RES_PATH: String = "res://data/config/server_admins.cfg"

static var _roles: Dictionary
static var _loaded: bool


## The role granted to an account via the config, or "" if none. Account match is
## case-insensitive.
static func role_for(account_name: String) -> String:
	if not _loaded:
		_load()
	return _roles.get(account_name.to_lower(), "")


## Re-read the file (e.g. after editing it without restarting the server).
static func reload() -> void:
	_roles.clear()
	_loaded = false


static func _load() -> void:
	_loaded = true
	var config: ConfigFile = ConfigFile.new()
	var path: String = USER_PATH if FileAccess.file_exists(USER_PATH) else RES_PATH
	if config.load(path) != OK or not config.has_section("admins"):
		return
	for account: String in config.get_section_keys("admins"):
		_roles[account.to_lower()] = str(config.get_value("admins", account, ""))
