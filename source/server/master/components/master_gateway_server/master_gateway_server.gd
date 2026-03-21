class_name GatewayManagerServer
extends BaseMultiplayerEndpoint


@export var world_manager: WorldManagerServer
@export var authentication_manager: AuthenticationManager


func _ready() -> void:
	var configuration: Dictionary = ConfigFileUtils.load_section(
		"gateway-manager-server",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/master_config.cfg")
	)
	create(Role.SERVER, configuration.bind_address, configuration.port)


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	print("Gateway: %d is connected to GatewayManager." % peer_id)
	update_worlds_info.rpc_id(peer_id, world_manager.connected_worlds)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Gateway: %d is disconnected from GatewayManager." % peer_id)


@rpc("any_peer", "call_remote")
func gateway_request(request_id: int, request: Dictionary) -> void:
	var gateway_id: int = multiplayer.get_remote_sender_id()
	if not request.has("action"):
		return
	var action: String = request.get("action", "")
	match action:
		"login":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				login_request(
					request[GatewayAPI.KEY_ACCOUNT_USERNAME],
					request[GatewayAPI.KEY_ACCOUNT_PASSWORD]
				)
			)
		"guest":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				create_account_request("", "", true)
			)
		"create_account":
			gateway_response.rpc_id(
				gateway_id,
				request_id,
				create_account_request(request[GatewayAPI.KEY_ACCOUNT_USERNAME], request[GatewayAPI.KEY_ACCOUNT_PASSWORD], false)
			)
		"create_character":
			create_player_character_request(
				gateway_id,
				request_id,
				request[GatewayAPI.KEY_ACCOUNT_USERNAME],
				request["data"],
				request[GatewayAPI.KEY_WORLD_ID]
			)
		"get_characters":
			request_player_characters(
				gateway_id,
				request_id,
				request[GatewayAPI.KEY_ACCOUNT_USERNAME],
				request[GatewayAPI.KEY_WORLD_ID]
			)
		"enter_world":
			request_enter_world(
				gateway_id,
				request_id,
				request[GatewayAPI.KEY_ACCOUNT_USERNAME],
				request[GatewayAPI.KEY_WORLD_ID],
				request[GatewayAPI.KEY_CHAR_ID],
			)


@rpc("authority", "call_remote")
func gateway_response(request_id: int, response: Dictionary) -> void:
	pass


@rpc("authority")
func update_worlds_info(_worlds_info: Dictionary) -> void:
	pass


func login_request(username: String, password: String) -> Dictionary:
	var account: AccountResource = authentication_manager.validate_credentials(
		username, password
	)

	if not account:
		return {"error": 50}
	elif account.peer_id:
		return {"error": 51}

	authentication_manager.active_accounts[account.username] = account

	# Check if latest world is online (needs rework)
	var last_connected_world_online: bool = false
	for world_id: int in world_manager.connected_worlds:
		if world_manager.connected_worlds.get(world_id, {}).get("info", {}).get("name", "") == account.last_world_name:
			last_connected_world_online = true
	if not last_connected_world_online:
		account.last_world_name = ""

	return {
		"name": account.username,
		"id": account.id,
		"world_name": account.last_world_name,
		"character_id": account.last_character_id,
		"w": world_manager.connected_worlds
	}


func create_account_request(username: String, password: String, is_guest: bool) -> Dictionary:
	var result_code: int
	var return_data: Dictionary
	var result: AccountResource = authentication_manager.create_account(username, password, is_guest)
	if result == null:
		result_code = 30
		return_data = {"error": result_code, "msg": "Couldn't create account."}
	else:
		return_data = {
			"name": result.username,
			"id": result.id,
			"w": world_manager.connected_worlds
		}
	return return_data


func create_player_character_request(
	gateway_id: int,
	request_id: int,
	username: String,
	character_data: Dictionary,
	world_id: int
) -> void:
	var account: AccountResource = authentication_manager.account_collection.collection.get(username)
	if not account:
		gateway_response.rpc_id(gateway_id, request_id, {"error": 50, "msg": "account not found."})
		return
	if not world_manager.connected_worlds.has(world_id):
		gateway_response.rpc_id(gateway_id, request_id, {"error": 50, "msg": "world not found."})
		return
	world_manager.create_player_character_request.rpc_id(
		world_id, gateway_id, request_id, account.username, character_data
	)


func request_player_characters(gateway_id: int, request_id: int, username: String, world_id: int) -> void:
	if (
		world_manager.connected_worlds.has(world_id)
		and authentication_manager.account_collection.collection.has(username)
	):
		var account: AccountResource = authentication_manager.account_collection.collection[username]
		world_manager.request_player_characters.rpc_id(
			world_id,
			gateway_id,
			request_id,
			username,
		)
	else:
		gateway_response.rpc_id(gateway_id, request_id, {"error": 50, "msg": "account not found or world."})


func request_enter_world(gateway_id: int, request_id: int, username: String, world_id: int, character_id: int) -> void:
	var account: AccountResource = authentication_manager.account_collection.collection.get(username)

	if not world_manager.connected_worlds.has(world_id):
		return

	account.last_world_name = world_manager.connected_worlds[world_id].get("info", {}).get("name", "")
	account.last_character_id = character_id
	if OS.has_feature("debug"):
		authentication_manager.save_account_collection()

	world_manager.request_login.rpc_id(
		world_id,
		gateway_id,
		request_id,
		username,
		character_id
	)
