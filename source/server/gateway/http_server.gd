extends "res://addons/httpserver/http_server.gd"


const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")

var next_request_id: int
var sessions: Dictionary[String, Dictionary]
var pending_requests: Dictionary[int, NetRequest]

@onready var gateway_manager_client: GatewayManagerClient = $"../GatewayManagerClient"


func _ready() -> void:
	super._ready()
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/login",
		handle_login
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/guest",
		handle_guest
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/world/character/create",
		handle_character_create
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/world/enter",
		handle_world_enter
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/world/characters",
		handle_world_characters
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/account/create",
		handle_account_creation
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/worlds",
		handle_worlds
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/handshake",
		handle_handshake
	)
	server.listen(8088, "127.0.0.1")
	
	gateway_manager_client.response_received.connect(
		_on_gateway_manager_client_response_received
	)


func create_session(account: Dictionary) -> String:
	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(32)
	var session_id: String = Marshalls.raw_to_base64(bytes)
	#session_id
	#account_id
	#created_at
	#last_seen_at
	#expires_at
	sessions[session_id] = account
	return session_id


func send_request(action: String, data: Dictionary, timeout_sec: float = 5.0) -> Dictionary:
	# The link up to the master may not be established yet at cold start. Bail with
	# a connection error rather than firing an RPC at an absent peer (which throws
	# ERR_CONNECTION_ERROR); the client treats this as retryable.
	if not gateway_manager_client.master_connected:
		return {"error": Error.ERR_TIMEOUT, "msg": "gateway not ready"}

	var request_id: int = next_request_id
	next_request_id += 1

	var request: NetRequest = NetRequest.new()
	request.token_id = data.get(GatewayAPI.KEY_TOKEN_ID, 0)
	pending_requests[request_id] = request
	
	data.merge({GatewayAPI.KEY_REQUEST_ID: request_id, "action": action}, true)
	
	gateway_manager_client.gateway_request.rpc_id(1, request_id, data)
	
	get_tree().create_timer(timeout_sec).timeout.connect(
		_on_request_timeout.bind(request_id)
	)
	
	return await request.completed


func _on_request_timeout(request_id: int) -> void:
	var request: NetRequest = pending_requests.get(request_id, null)
	if not request:
		return
	request.resolve({"error": Error.ERR_TIMEOUT, "msg": "request timeout"})


func _on_gateway_manager_client_response_received(request_id: int, response: Dictionary) -> void:
	var request: NetRequest = pending_requests.get(request_id, null)
	if not request:
		return
	request.resolve(response)


# Per-IP throttle for the brute-forceable / spammable auth endpoints. __ip__ is the
# real client even behind Caddy — the HTTP addon reads the X-Real-IP header Caddy
# stamps (header_up X-Real-IP {remote_host}), falling back to the socket host. So
# loopback stays exempt only for local multi-instance testing (no proxy header).
func _rate_ok(payload: Dictionary, endpoint: StringName, max_calls: int, window_ms: int) -> bool:
	var ip: String = str(payload.get("__ip__", ""))
	if ip.is_empty() or ip == "127.0.0.1" or ip == "::1":
		return true
	return AuthRateLimiter.allow(ip, endpoint, max_calls, window_ms)


## Exact-match version gate (server build == client build). Returns {} when OK, else
## {error: ERR_OUTDATED_VERSION, msg}. Shared by login + the boot handshake so the
## two never drift.
func _check_version(payload: Dictionary) -> Dictionary:
	var server_version: String = GatewayAPI.game_version()
	var client_version: String = str(payload.get(GatewayAPI.KEY_CLIENT_VERSION, ""))
	if client_version == server_version:
		return {}
	var have: String = client_version if not client_version.is_empty() else "unknown"
	return {
		"error": GatewayAPI.ERR_OUTDATED_VERSION,
		"msg": "Outdated game version — please update. (server %s, you have %s)" % [server_version, have],
	}


## Boot healthcheck (no auth): the gateway client calls this before showing any menu.
## OK only when the build matches AND the master link is up (so a login would land).
func handle_handshake(payload: Dictionary) -> Dictionary:
	var version_check: Dictionary = _check_version(payload)
	if not version_check.is_empty():
		return version_check
	if not gateway_manager_client.master_connected:
		return {"error": Error.ERR_TIMEOUT, "msg": "gateway not ready"}
	return {"ok": true}


func handle_login(payload: Dictionary) -> Dictionary:
	if not _rate_ok(payload, &"login", 10, 60000):
		return {"error": GatewayAPI.ERR_RATE_LIMITED}
	if not payload.has_all(
		[
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_ACCOUNT_PASSWORD
		]
	):
		return {"error": "invalid_payload"}
	# Version gate (shared with the boot handshake) — reject a mismatched build.
	var version_check: Dictionary = _check_version(payload)
	if not version_check.is_empty():
		return version_check
	var result: Dictionary = await send_request("login", payload)
	var error: Error = result.get("error", 0)
	if error != OK:
		return result
	
	result["session_id"] = create_session(result)
	return result


func handle_guest(payload: Dictionary) -> Dictionary:
	if not _rate_ok(payload, &"guest", 5, 60000):
		return {"error": GatewayAPI.ERR_RATE_LIMITED}
	var result: Dictionary = await send_request("guest", payload)
	var error: Error = result.get("error", 0)
	if error != OK:
		return {"error": error}
	
	result["session_id"] = create_session(result)
	return result


func handle_character_create(payload: Dictionary) -> Dictionary:
	if not payload.has_all(
		[
			GatewayAPI.KEY_TOKEN_ID,
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_WORLD_ID,
			"data"
		]
	):
		return {"error": "invalid_payload"}

	var character_data: Dictionary = payload.get("data", null) as Dictionary
	if character_data.is_empty():
		return {"error": 1}
	var result: Dictionary = CredentialsUtils.validate_username(character_data.get("name", ""))
	if result.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"error": result}

	var response: Dictionary = await send_request("create_character", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		return response

	return response


func handle_world_characters(payload: Dictionary) -> Dictionary:
	if not payload.has_all(
		[
			GatewayAPI.KEY_TOKEN_ID,
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_WORLD_ID,
		]
	):
		return {"error": "invalid_payload"}

	var response: Dictionary = await send_request("get_characters", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		return response

	return response



func handle_world_enter(payload: Dictionary) -> Dictionary:
	if not payload.has_all(
		[
			GatewayAPI.KEY_TOKEN_ID,
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_WORLD_ID,
			GatewayAPI.KEY_CHAR_ID
		]
	):
		return {"error": "invalid_payload"}

	var response: Dictionary = await send_request("enter_world", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		return {"error": error}

	return response


## Cheap world-list refresh: served straight from the gateway's cached roster
## (the master broadcasts it on every world connect/disconnect), so no master
## round-trip per refresh. Used by the client's "Update" button and the
## empty-state auto-retry.
func handle_worlds(_payload: Dictionary) -> Dictionary:
	return {"w": _public_worlds(gateway_manager_client.worlds_info)}


## Whitelist only what a world card needs. The cached roster also carries each
## world's address, port and full heartbeat snapshot (player rosters, chat tail,
## server logs) — never ship those to a game client.
func _public_worlds(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for world_id: Variant in raw:
		var info: Dictionary = raw[world_id].get("info", {})
		out[world_id] = {
			"info": {
				"name": info.get("name", ""),
				"motd": info.get("motd", ""),
				"pvp": info.get("pvp", false),
			}
		}
	return out


func handle_account_creation(payload: Dictionary) -> Dictionary:
	if not _rate_ok(payload, &"account_create", 5, 300000):
		return {"error": GatewayAPI.ERR_RATE_LIMITED}
	if not payload.has_all(
		[
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_ACCOUNT_PASSWORD,
		]
	):
		return {"error": "invalid_payload"}

	# Validate server-side too — never trust the client's pre-check (length, chars,
	# reserved names). Same CredentialsUtils the client uses, so messages match.
	var username: String = str(payload.get(GatewayAPI.KEY_ACCOUNT_USERNAME, ""))
	var password: String = str(payload.get(GatewayAPI.KEY_ACCOUNT_PASSWORD, ""))
	var uname_check: Dictionary = CredentialsUtils.validate_username(username)
	if uname_check.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"error": str(uname_check.get("message", "Invalid username."))}
	var pass_check: Dictionary = CredentialsUtils.validate_password(password)
	if pass_check.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"error": str(pass_check.get("message", "Invalid password."))}

	var response: Dictionary = await send_request("create_account", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		return {"error": error}

	return response
