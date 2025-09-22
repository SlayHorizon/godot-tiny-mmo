extends "res://addons/httpserver/http_server.gd"


var next_id: int

@onready var gateway_manager_client: GatewayManagerClient = $"../GatewayManagerClient"


func _ready() -> void:
	#set_physics_process(false)
	#return
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
	gateway_manager_client.create_player_character_request.rpc_id(
		1,
		payload["t-id"],
		payload["a-u"],
		payload["data"],
		payload["w-id"]
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
