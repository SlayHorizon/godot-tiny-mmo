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


@rpc("authority")
func update_worlds_info(_worlds_info: Dictionary) -> void:
	pass


# Send an authentication auth_token to the gateway for a specific peer,
# used by the peer to connect to a game server.
@rpc("authority")
func fetch_auth_token(_target_peer: int, _auth_token: String, _address: String, _port: int) -> void:
	pass


@rpc("any_peer")
func login_request(peer_id: int, username: String, password: String) -> void:
	var gateway_id: int = multiplayer.get_remote_sender_id()
	var account: AccountResource = authentication_manager.validate_credentials(
		username, password
	)
	if not account:
		login_result.rpc_id(gateway_id, peer_id, {"error": 50})
	elif account.peer_id:
		login_result.rpc_id(gateway_id, peer_id, {"error": 51})
	else:
		account.peer_id = peer_id
		# Check if latest world is online (needs rework)
		var last_connected_world_online: bool = false
		for world_id: int in world_manager.connected_worlds:
			if world_manager.connected_worlds.get(world_id, {}).get("info", {}).get("name", "") == account.last_world_name:
				last_connected_world_online = true
		if not last_connected_world_online:
			account.last_world_name = ""
		login_result.rpc_id(
			gateway_id, peer_id,
			{
				"name": account.username,
				"id": account.id,
				"world_name": account.last_world_name,
				"character_id": account.last_character_id
			}
		)


@rpc("authority")
func login_result(_peer_id: int, _result: Dictionary) -> void:
	pass



@rpc("any_peer")
func create_account_request(peer_id: int, username: String, password: String, is_guest: bool) -> void:
	var gateway_id: int = multiplayer_api.get_remote_sender_id()
	var result_code: int = 0
	var return_data: Dictionary = {}
	var result: AccountResource = authentication_manager.create_account(username, password, is_guest)
	if result == null:
		result_code = 30
	else:
		return_data = {"name": result.username, "id": result.id}
		result.peer_id = peer_id
	account_creation_result.rpc_id(gateway_id, peer_id, result_code, return_data)



@rpc("authority")
func account_creation_result(_peer_id: int, _result_code: int, _data: Dictionary) -> void:
	pass


# Used to create the player's character.
@rpc("any_peer")
func create_player_character_request(peer_id: int, username: String, character_data: Dictionary, world_id: int) -> void:
	var gateway_id: int = multiplayer_api.get_remote_sender_id()
	var account: AccountResource = authentication_manager.account_collection.collection.get(username)
	if not account or account.peer_id != peer_id:
		return
	if not world_manager.connected_worlds.has(world_id):
		return
	world_manager.create_player_character_request.rpc_id(
		world_id, gateway_id, peer_id, account.username, character_data
	)


@rpc("authority")
func player_character_creation_result(_peer_id: int, result: Dictionary) -> void:
	pass


@rpc("any_peer")
func request_player_characters(peer_id: int, username: String, world_id: int) -> void:
	var gateway_id: int = multiplayer_api.get_remote_sender_id()
	if (
		world_manager.connected_worlds.has(world_id)
		and authentication_manager.account_collection.collection.has(username)
	):
		var account := authentication_manager.account_collection.collection[username] as AccountResource
		if account.peer_id == peer_id:
			world_manager.request_player_characters.rpc_id(
				world_id,
				gateway_id,
				peer_id,
				username,
			)


@rpc("authority")
func receive_player_characters(_player_characters: Dictionary) -> void:
	pass


@rpc("any_peer")
func request_login(peer_id: int, username: String, world_id: int, character_id: int) -> void:
	var gateway_id: int = multiplayer_api.get_remote_sender_id()
	var account: AccountResource = authentication_manager.account_collection.collection.get(username)
	if not account or account.peer_id != peer_id:
		return

	if not world_manager.connected_worlds.has(world_id):
		return

	account.last_world_name = world_manager.connected_worlds[world_id].get("info", {}).get("name", "")
	account.last_character_id = character_id
	if OS.has_feature("debug"):
		authentication_manager.save_account_collection()
	world_manager.request_login.rpc_id(
		world_id,
		gateway_id,
		peer_id,
		username,
		character_id
	)


@rpc("any_peer")
func peer_disconnected_without_joining_world(account_name: String) -> void:
	if authentication_manager.account_collection.collection.has(account_name):
		authentication_manager.account_collection.collection[account_name].peer_id = 0
