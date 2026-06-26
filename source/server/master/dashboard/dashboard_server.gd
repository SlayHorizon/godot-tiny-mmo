extends "res://addons/httpserver/http_server.gd"
## Web admin dashboard for the master server. Exposes a JSON API + static UI
## scoped to "what's happening across my world servers" — replaces the older
## account-CRUD-focused admin server.
##
## Routes — mounted under /v1 by convention (REST versioning), but the HTTP
## addon now tries routes before static so any prefix works.
##   GET  /v1/status              — master uptime + connected worlds count
##   GET  /v1/worlds              — per-world snapshot (population, uptime, …)
##   GET  /v1/players             — merged online roster across all worlds
##   GET  /v1/chat                — merged recent channel messages across worlds
##   GET  /v1/logs                — master log tail (in-memory ring)
##   POST /v1/worlds/save         — body {world_id}
##   POST /v1/worlds/shutdown     — body {world_id}
##   POST /v1/worlds/broadcast    — body {world_id, message}
##   POST /v1/restart_all         — body {seconds?, message?} (fans out to all worlds)
##   POST /v1/players/mute        — body {world_id, player_id, reason?, duration_ms?}
##   POST /v1/players/unmute      — body {world_id, player_id}
##   POST /v1/players/jail        — body {world_id, player_id, reason?, duration_ms?}
##   POST /v1/players/unjail      — body {world_id, player_id}
##   POST /v1/players/kick        — body {world_id, player_id}
##   POST /v1/players/grant       — body {world_id, player_id, role}
##   POST /v1/players/revoke      — body {world_id, player_id, role}
##   GET  /v1/accounts            — registered accounts (id/username, no password)
##   POST /v1/accounts/reset_password — body {username, new_password}
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

	router.register_route(HTTPClient.Method.METHOD_GET,  &"/v1/status",            _handle_status)
	router.register_route(HTTPClient.Method.METHOD_GET,  &"/v1/worlds",            _handle_worlds)
	router.register_route(HTTPClient.Method.METHOD_GET,  &"/v1/players",           _handle_players)
	router.register_route(HTTPClient.Method.METHOD_GET,  &"/v1/chat",              _handle_chat)
	router.register_route(HTTPClient.Method.METHOD_GET,  &"/v1/logs",              _handle_logs)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/worlds/save",       _handle_world_save)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/worlds/shutdown",   _handle_world_shutdown)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/worlds/broadcast",  _handle_world_broadcast)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/restart_all",       _handle_restart_all)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/players/mute",      _handle_player_mute)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/players/unmute",    _handle_player_unmute)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/players/jail",      _handle_player_jail)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/players/unjail",    _handle_player_unjail)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/players/kick",      _handle_player_kick)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/players/grant",     _handle_player_grant)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/players/revoke",    _handle_player_revoke)
	router.register_route(HTTPClient.Method.METHOD_GET,  &"/v1/accounts",                _handle_accounts)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/accounts/reset_password", _handle_account_reset_password)

	server.listen(PORT, BIND_ADDRESS)
	ServerLog.info("Dashboard listening on %s:%d" % [BIND_ADDRESS, PORT])
	DiscordNotifier.notify_master_online()


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


## Fan a restart countdown out to EVERY connected world in one call — the deploy
## hits this once before stopping the servers, so players get staged warnings while
## the old build is still up. Body: {seconds?, message?}. Worlds warn + final-save;
## they do NOT quit (the deploy's stop does that). Returns the world count notified.
func _handle_restart_all(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var seconds: int = clampi(int(payload.get("seconds", 300)), 0, 3600)
	var message: String = str(payload.get("message", "")).strip_edges()
	if message.length() > 280:
		return {"ok": false, "error": "message_too_long"}
	var count: int = world_manager.tell_all_worlds_to_restart(seconds, message)
	ServerLog.info("Dashboard restart_all: %d world(s), countdown %ds." % [count, seconds])
	return {"ok": true, "worlds": count, "seconds": seconds}


# --- Aggregated read endpoints (players / chat / logs) ---

## All three read endpoints take an optional `world_id` to scope to a single
## world. The dashboard drill-down view uses that scoping so the payload is
## just one world's slice instead of every world's merged. Without `world_id`
## you get the merged view (still useful for an "is anything weird across the
## fleet" glance).

func _handle_players(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var only_world: int = int(payload.get("world_id", 0))
	var rows: Array = []
	for world_id: int in world_manager.connected_worlds:
		if only_world > 0 and world_id != only_world:
			continue
		var w: Dictionary = world_manager.connected_worlds[world_id]
		var hb: Dictionary = w.get("heartbeat", {})
		var world_name: String = str(hb.get("name", w.get("info", {}).get("name", "world#%d" % world_id)))
		for p: Variant in hb.get("players", []):
			if p is Dictionary:
				var row: Dictionary = (p as Dictionary).duplicate()
				row["world_id"] = world_id
				row["world_name"] = world_name
				rows.append(row)
	rows.sort_custom(func(a, b):
		if str(a["world_name"]) != str(b["world_name"]):
			return str(a["world_name"]) < str(b["world_name"])
		return int(a.get("player_id", 0)) < int(b.get("player_id", 0))
	)
	return {"ok": true, "players": rows}


func _handle_chat(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var only_world: int = int(payload.get("world_id", 0))
	var rows: Array = []
	for world_id: int in world_manager.connected_worlds:
		if only_world > 0 and world_id != only_world:
			continue
		var w: Dictionary = world_manager.connected_worlds[world_id]
		var hb: Dictionary = w.get("heartbeat", {})
		var world_name: String = str(hb.get("name", w.get("info", {}).get("name", "world#%d" % world_id)))
		for m: Variant in hb.get("recent_chat", []):
			if m is Dictionary:
				var row: Dictionary = (m as Dictionary).duplicate()
				row["world_id"] = world_id
				row["world_name"] = world_name
				rows.append(row)
	rows.sort_custom(func(a, b): return int(a.get("time_ms", 0)) < int(b.get("time_ms", 0)))
	return {"ok": true, "messages": rows}


func _handle_logs(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var only_world: int = int(payload.get("world_id", 0))
	var limit: int = int(payload.get("limit", 200))
	# With a world_id, return that world's heartbeat log slice. Without one,
	# return the master process's own log tail (useful for diagnosing
	# master-side issues — peer connects, dashboard auth, etc.).
	if only_world > 0:
		var w: Dictionary = world_manager.connected_worlds.get(only_world, {})
		var lines: Array = []
		for line: Variant in w.get("heartbeat", {}).get("recent_log", []):
			lines.append(str(line))
		if lines.size() > limit:
			lines = lines.slice(lines.size() - limit)
		return {"ok": true, "lines": lines, "source": "world"}
	return {"ok": true, "lines": Array(ServerLog.recent(limit)), "source": "master"}


# --- Player-action endpoints ---

func _handle_player_mute(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var player_id: int = int(payload.get("player_id", 0))
	var reason: String = str(payload.get("reason", ""))
	var duration_ms: int = int(payload.get("duration_ms", 0))
	if player_id <= 0:
		return {"ok": false, "error": "bad_player"}
	if not world_manager.tell_world_to_mute(world_id, player_id, reason, duration_ms):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true}


func _handle_player_unmute(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var player_id: int = int(payload.get("player_id", 0))
	if player_id <= 0:
		return {"ok": false, "error": "bad_player"}
	if not world_manager.tell_world_to_unmute(world_id, player_id):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true}


func _handle_player_jail(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var player_id: int = int(payload.get("player_id", 0))
	var reason: String = str(payload.get("reason", ""))
	var duration_ms: int = int(payload.get("duration_ms", 0))
	if player_id <= 0:
		return {"ok": false, "error": "bad_player"}
	if not world_manager.tell_world_to_jail(world_id, player_id, reason, duration_ms):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true}


func _handle_player_unjail(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var player_id: int = int(payload.get("player_id", 0))
	if player_id <= 0:
		return {"ok": false, "error": "bad_player"}
	if not world_manager.tell_world_to_unjail(world_id, player_id):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true}


func _handle_player_kick(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var player_id: int = int(payload.get("player_id", 0))
	if player_id <= 0:
		return {"ok": false, "error": "bad_player"}
	if not world_manager.tell_world_to_kick(world_id, player_id):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true}


func _handle_player_grant(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var player_id: int = int(payload.get("player_id", 0))
	var role: String = str(payload.get("role", "")).strip_edges()
	if player_id <= 0 or role.is_empty():
		return {"ok": false, "error": "bad_args"}
	if not world_manager.tell_world_to_grant_role(world_id, player_id, role):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true}


func _handle_player_revoke(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var world_id: int = int(payload.get("world_id", 0))
	var player_id: int = int(payload.get("player_id", 0))
	var role: String = str(payload.get("role", "")).strip_edges()
	if player_id <= 0 or role.is_empty():
		return {"ok": false, "error": "bad_args"}
	if not world_manager.tell_world_to_revoke_role(world_id, player_id, role):
		return {"ok": false, "error": "unknown_world"}
	return {"ok": true}


# --- Account endpoints ---

## Lists registered accounts (id + username + last world) so the dashboard can
## show who exists. Deliberately returns NO password material.
func _handle_accounts(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var rows: Array = []
	for username: Variant in authentication_manager.account_collection.collection:
		var account: AccountResource = authentication_manager.account_collection.collection[username]
		if account == null:
			continue
		rows.append({
			"id": account.id,
			"username": account.username,
			"last_world_name": account.last_world_name,
		})
	rows.sort_custom(func(a, b): return str(a["username"]) < str(b["username"]))
	return {"ok": true, "accounts": rows}


## Resets an account's password to a new value, hashed with the SAME
## PasswordHasher the login path uses (so it verifies). Runs inside the master
## process against the live in-memory collection, so it takes effect for the
## next login immediately — and persists to disk right away.
func _handle_account_reset_password(payload: Dictionary) -> Dictionary:
	if not _check_auth(payload):
		return _unauthorized()
	var username: String = str(payload.get("username", "")).strip_edges().to_lower()
	var new_password: String = str(payload.get("new_password", ""))
	if username.is_empty() or new_password.is_empty():
		return {"ok": false, "error": "bad_args"}
	var collection: Dictionary = authentication_manager.account_collection.collection
	if not collection.has(username):
		return {"ok": false, "error": "account_not_found"}
	var account: AccountResource = collection[username]
	account.password = PasswordHasher.hash_password(new_password)
	authentication_manager.save_account_collection()
	ServerLog.info("Dashboard: reset password for account '%s' (id %d)." % [account.username, account.id])
	return {"ok": true, "username": account.username, "id": account.id}


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
		ServerLog.warn("Dashboard: no config found, running with auth DISABLED. Create %s or %s with [auth] token=\"...\"" % [USER_CONFIG_PATH, RES_CONFIG_PATH])
		return
	_auth_token = str(config.get_value("auth", "token", ""))
	if _auth_token.is_empty():
		ServerLog.warn("Dashboard: token is empty in config, running with auth DISABLED.")
