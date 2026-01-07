extends "res://addons/httpserver/http_server.gd"

@onready var authentication_manager: AuthenticationManager = $"../AuthenticationManager"

const PREVIEW_LIMIT: int = 50
const ALLOW_PASSWORD_READ: bool = false
const ALLOW_PASSWORD_WRITE: bool = false


func _ready() -> void:
	super._ready()

	router.register_route(HTTPClient.Method.METHOD_GET, &"/v1/ping", handle_ping)
	router.register_route(HTTPClient.Method.METHOD_GET, &"/v1/overview", handle_overview)

	router.register_route(HTTPClient.Method.METHOD_GET, &"/v1/accounts", handle_show_accounts)
	router.register_route(HTTPClient.Method.METHOD_GET, &"/v1/accounts/find", handle_find_accounts_get)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/accounts/find", handle_find_accounts_post)
	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/accounts/update", handle_update_account)

	router.register_route(HTTPClient.Method.METHOD_POST, &"/v1/save", handle_save)

	server.listen(8089, "127.0.0.1")


func handle_ping(_payload: Dictionary) -> Dictionary:
	return {"ok": true, "ts": Time.get_unix_time_from_system()}


func handle_overview(_payload: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"online_players": 0,
		"registered_accounts": _get_registered_accounts_count(),
	}


func handle_show_accounts(_payload: Dictionary) -> Dictionary:
	var col: Dictionary = authentication_manager.account_collection.collection
	var keys: Array = col.keys()
	keys.sort()

	var preview: Array = []
	var total: int = keys.size()

	for i: int in range(min(PREVIEW_LIMIT, total)):
		var username: String = str(keys[i])
		var account: AccountResource = col.get(username)
		if account != null:
			preview.append(_account_to_dict(account))

	return {
		"ok": true,
		"total": total,
		"preview_limit": PREVIEW_LIMIT,
		"preview": preview,
	}


func handle_find_accounts_get(payload: Dictionary) -> Dictionary:
	var q: String = str(payload.get("q", "")).strip_edges()
	return _find_accounts(q)


func handle_find_accounts_post(payload: Dictionary) -> Dictionary:
	var q: String = str(payload.get("q", "")).strip_edges()
	return _find_accounts(q)


func _find_accounts(q: String) -> Dictionary:
	if q.is_empty():
		return {"ok": true, "query": q, "total_matches": 0, "matches": []}

	var col: Dictionary = authentication_manager.account_collection.collection
	var q_lower: String = q.to_lower()

	var matches: Array = []

	for username: Variant in col.keys():
		var u: String = str(username)
		var account: AccountResource = col.get(u)
		if account == null:
			continue

		if u.to_lower().find(q_lower) != -1 or str(account.id).find(q_lower) != -1:
			matches.append(_account_to_dict(account))
			if matches.size() >= PREVIEW_LIMIT:
				break

	return {
		"ok": true,
		"query": q,
		"total_matches": matches.size(),
		"limit": PREVIEW_LIMIT,
		"matches": matches,
	}


func handle_update_account(payload: Dictionary) -> Dictionary:
	var patch: Dictionary = payload.get("patch", {}) as Dictionary
	if patch.is_empty():
		return {"ok": false, "error": "missing_patch"}

	var col: Dictionary = authentication_manager.account_collection.collection

	var account: AccountResource = null
	var current_username: String = ""

	if payload.has("username"):
		current_username = str(payload["username"])
		account = col.get(current_username)
	elif payload.has("id"):
		var found: Dictionary = _find_account_by_id(int(payload["id"]))
		account = found["account"]
		current_username = found["username"]
	else:
		return {"ok": false, "error": "missing_identifier"}

	if account == null:
		return {"ok": false, "error": "account_not_found"}

	if patch.has("peer_id"):
		account.peer_id = int(patch["peer_id"])

	if patch.has("username"):
		var new_username: String = str(patch["username"]).strip_edges()
		if new_username.is_empty():
			return {"ok": false, "error": "invalid_username"}

		if new_username != current_username and col.has(new_username):
			return {"ok": false, "error": "username_exists"}

		account.username = new_username

		if new_username != current_username:
			col.erase(current_username)
			col[new_username] = account
			current_username = new_username

	if patch.has("password"):
		if not ALLOW_PASSWORD_WRITE:
			return {"ok": false, "error": "password_write_disabled"}
		account.password = str(patch["password"])

	return {
		"ok": true,
		"updated": _account_to_dict(account),
		"note": "Call /v1/save to persist to disk.",
	}


func _find_account_by_id(id: int) -> Dictionary:
	var col: Dictionary = authentication_manager.account_collection.collection

	for username: Variant in col.keys():
		var account: AccountResource = col.get(username)
		if account != null and account.id == id:
			return {"account": account, "username": str(username)}

	return {"account": null, "username": ""}


func handle_save(_payload: Dictionary) -> Dictionary:
	authentication_manager.save_account_collection()
	return {"ok": true, "message": "Saved."}


func _get_registered_accounts_count() -> int:
	return authentication_manager.account_collection.collection.size()


func _account_to_dict(account: AccountResource) -> Dictionary:
	var d: Dictionary = {
		"id": account.id,
		"username": account.username,
		"peer_id": account.peer_id,
		"has_password": not str(account.password).is_empty(),
	}

	if ALLOW_PASSWORD_READ:
		d["password"] = account.password

	return d
