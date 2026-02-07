extends "res://addons/httpserver/http_server.gd"


const GatewayApi: GDScript = preload("res://source/common/network/gateway_api.gd")
const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")

var next_id: int

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
	server.listen(8088, "127.0.0.1")


func handle_login(payload: Dictionary) -> Dictionary:
	gateway_manager_client.login_request.rpc_id(
		1,
		payload["t-id"],
		payload["u"],
		payload["p"]
	)
	while true:
		var d: Dictionary = await gateway_manager_client.response_received
		if d.get("t-id", -1) == payload["t-id"]:
			return d
	return {"access_token":"abc","refresh_token":"r1","expires_in":900}


func handle_guest(payload: Dictionary) -> Dictionary:
	gateway_manager_client.create_account_request.rpc_id(1, payload["t-id"], "", "", true)
	while true:
		var d: Dictionary = await gateway_manager_client.response_received
		if d.get("t-id", -1) == payload["t-id"]:
			return d
	return {"error": 1}


func handle_character_create(payload: Dictionary) -> Dictionary:
	if not payload.has_all(
		[GatewayApi.KEY_TOKEN_ID, GatewayApi.KEY_ACCOUNT_USERNAME,
		"data", GatewayApi.KEY_WORLD_ID]
	):
		return {"error": 1}
	var character_data: Dictionary = payload.get("data", null) as Dictionary
	if character_data.is_empty():
		return {"error": 1}
	var result: Dictionary = CredentialsUtils.validate_username(character_data.get("name", ""))
	if result.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"error": result}
	gateway_manager_client.create_player_character_request.rpc_id(
		1,
		payload[GatewayApi.KEY_TOKEN_ID],
		payload[GatewayApi.KEY_ACCOUNT_USERNAME],
		payload["data"],
		payload[GatewayApi.KEY_WORLD_ID]
	)
	while true:
		var d: Dictionary = await gateway_manager_client.response_received
		if d.get("t-id", -1) == payload["t-id"]:
			return d
	return {"error": 1}


func handle_world_characters(payload: Dictionary) -> Dictionary:
	gateway_manager_client.request_player_characters.rpc_id(
		1,
		payload["t-id"],
		payload["a-u"],
		payload["w-id"]
	)
	while true:
		var d: Dictionary = await gateway_manager_client.response_received
		if d.get("t-id", -1) == payload["t-id"]:
			return d
	return {"error": 1}


func handle_world_enter(payload: Dictionary) -> Dictionary:
	gateway_manager_client.request_login.rpc_id(
		1,
		payload["t-id"],
		payload["a-u"],
		payload["w-id"],
		payload["c-id"],
	)
	while true:
		var d: Dictionary = await gateway_manager_client.response_received
		if d.get("t-id", -1) == payload["t-id"]:
			return d
	return {"error": 1}


func handle_account_creation(payload: Dictionary) -> Dictionary:
	gateway_manager_client.create_account_request.rpc_id(
		1,
		payload["t-id"],
		payload["u"],
		payload["p"],
		false
	)
	while true:
		var d: Dictionary = await gateway_manager_client.response_received
		if d.get("t-id", -1) == payload["t-id"]:
			return d
	return {"error": 1}
