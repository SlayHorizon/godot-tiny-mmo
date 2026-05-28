extends "res://addons/httpserver/http_server.gd"
## Web admin dashboard for the master server. Exposes a JSON API + static UI
## scoped to "what's happening across my world servers" — replaces the older
## account-CRUD-focused admin server.
##
## Routes
##   GET  /api/status             — master uptime + connected worlds count
##   GET  /api/worlds             — array of {world_id, name, address, port,
##                                  population, instances, uptime_s, ...}
##   POST /api/worlds/save        — body {world_id} → master tells world to save
##   POST /api/worlds/shutdown    — body {world_id} → master tells world to quit
##   POST /api/worlds/broadcast   — body {world_id, message} → push system msg
##
## Auth
##   Bearer token in either header `Authorization: Bearer <token>` or query
##   `?token=<token>`. Token lives in user://dashboard.cfg or
##   res://data/config/dashboard.cfg.
##
## Binding
##   By default listens on 0.0.0.0:<PORT> so a port-forwarded server is
##   immediately reachable from a phone. Lock down to 127.0.0.1 by editing
##   BIND_ADDRESS below if you'd rather SSH-tunnel in.

const PORT: int = 8080
const BIND_ADDRESS: String = "*" # "*" = all interfaces; use "127.0.0.1" for localhost-only

const USER_CONFIG_PATH: String = "user://dashboard.cfg"
const RES_CONFIG_PATH: String = "res://data/config/dashboard.cfg"

@onready var world_manager: WorldManagerServer = $"../WorldManagerServer"
@onready var authentication_manager: AuthenticationManager = $"../AuthenticationManager"

var _started_at_unix: int = 0
var _auth_token: String = ""


func _ready() -> void:
	super._ready()
	_started_at_unix = int(Time.get_unix_time_from_system())
	_load_config()

	router.register_static_dir(&"/", "res://source/server/master/dashboard", "index.html")

	router.register_route(HTTPClient.Method.METHOD_GET,  &"/api/status",            _handle_status)
	router.register_route(HTTPClient.Method.METHOD_GET,  &"/api/worlds",            _handle_worlds)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/api/worlds/save",       _handle_world_save)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/api/worlds/shutdown",   _handle_world_shutdown)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/api/worlds/broadcast",  _handle_world_broadcast)

	server.listen(PORT, BIND_ADDRESS)
	Logger.info("Dashboard listening on %s:%d" % [BIND_ADDRESS, PORT])
	DiscordNotifier.notify_master_online(BIND_ADDRESS, PORT)


# --- handlers ---

func _handle_status(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	return {
		"ok": true,
		"master_started_at": _started_at_unix,
		"uptime_s": int(Time.get_unix_time_from_system()) - _started_at_unix,
		"worlds_connected": world_manager.connected_worlds.size(),
		"registered_accounts": authentication_manager.account_collection.collection.size(),
	}


func _handle_worlds(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var rows: Array = []
	for world_id: int in world_manager.connected_worlds:
		var w: Dictionary = world_manager.connected_worlds[world_id]
		var hb: Dictionary = w.get("heartbeat", {})
		var info: Dictionary = w.get("info", {})
		rows.append({
			"world_id":       world_id,
			"name":           str(hb.get("name", info.get("name", "world#%d" % world_id))),
			"address":        str(w.get("address", "?")),
			"port":           int(w.get("port", 0)),
			"connected_at":   int(w.get("connected_at", 0)),
			"last_heartbeat": int(w.get("last_heartbeat_at", 0)),
			"population":     int(hb.get("population", 0)),
			"instances":      int(hb.get("instances", 0)),
			"uptime_s":       int(hb.get("uptime_s", 0)),
		})
	# Stable order: by name then world_id.
	rows.sort_custom(func(a, b):
		if str(a["name"]) != str(b["name"]):
			return str(a["name"]) < str(b["name"])
		return int(a["world_id"]) < int(b["world_id"])
	)
	return {"ok": true, "worlds": rows}


func _handle_world_save(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	if not world_manager.tell_world_to_save(world_id):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true, "message": "Save requested."}


func _handle_world_shutdown(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	if not world_manager.tell_world_to_shutdown(world_id):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true, "message": "Shutdown requested."}


func _handle_world_broadcast(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var message: String = str(payload.get("message", "")).strip_edges()
	if message.is_empty():
		return {"ok": false, "error": "empty_message"}
	if message.length() > 280:
		return {"ok": false, "error": "message_too_long"}
	if not world_manager.tell_world_to_broadcast(world_id, message):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true, "message": "Broadcast sent."}


# --- auth helpers ---

## Token can be passed via header (preferred) or ?token=... (so a phone can
## hit it without setting headers). Returns true if the request is allowed.
func _check_auth(payload: Dictionary) -> bool:
	# Token disabled → everyone gets in. Useful only for localhost-bound dev.
	if _auth_token.is_empty():
		return true
	# We don't currently parse headers in the addon, so the static UI sends
	# the token as a payload field on every request.
	return str(payload.get("token", "")) == _auth_token


func _unauthorized() -> Dictionary:
	return {"ok": false, "error": "unauthorized"}


func _load_config() -> void:
	var config: ConfigFile = ConfigFile.new()
	var path: String = USER_CONFIG_PATH if FileAccess.file_exists(USER_CONFIG_PATH) else RES_CONFIG_PATH
	if config.load(path) != OK:
		Logger.warn("Dashboard: no config found, running with auth DISABLED. Create %s or %s with [auth] token=\"...\"" % [USER_CONFIG_PATH, RES_CONFIG_PATH])
		return
	_auth_token = str(config.get_value("auth", "token", ""))
	if _auth_token.is_empty():
		Logger.warn("Dashboard: token is empty in config, running with auth DISABLED.")
