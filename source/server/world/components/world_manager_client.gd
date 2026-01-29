class_name WorldManagerClient
extends BaseMultiplayerEndpoint


signal token_received(auth_token: String, username: String, character_id: int)

@export var database: WorldDatabase
@export var world_server: WorldServer

var world_info: Dictionary


func start_client_to_master_server(_world_info: Dictionary) -> void:
	
	world_info = _world_info
	var configuration: Dictionary = ConfigFileUtils.load_section(
		"world-manager-client",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/world_config.cfg")
	)
	create(Role.CLIENT, configuration.address, configuration.port)


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.connected_to_server.connect(_on_connection_succeeded)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)


func _on_connection_succeeded() -> void:
	print("Successfully connected to the Gateway as %d!" % multiplayer.get_unique_id())
	fetch_server_info.rpc_id(
		1,
		{
			"port": world_info.port,
			"address": "127.0.0.1",
			"info": world_info,
			"population": world_server.connected_players.size()
		}
	)


func _on_connection_failed() -> void:
	print("Failed to connect to the MasterServer as WorldServer.")


func _on_server_disconnected() -> void:
	print("Game Server disconnected.")


@rpc("any_peer")
func fetch_server_info(_info: Dictionary) -> void:
	pass


@rpc("authority")
func fetch_token(auth_token: String, username: String, character_id: int) -> void:
	token_received.emit(auth_token, username, character_id)


@rpc("any_peer")
func player_disconnected(_username: String) -> void:
	pass


@rpc("authority")
func create_player_character_request(gateway_id: int, peer_id: int, username: String, character_data: Dictionary) -> void:
	var character_id: int = database.create_player_character(username, character_data)
	
	player_character_creation_result.rpc_id(
		1,
		gateway_id,
		peer_id,
		username,
		character_id
	)


@rpc("any_peer")
func player_character_creation_result(_gateway_id: int, _peer_id: int, _username: String, _result_code: int) -> void:
	pass


@rpc("authority")
func request_player_characters(gateway_id: int, peer_id: int, username: String) -> void:
	var characters: Dictionary = database.get_account_characters(username)
	
	receive_player_characters.rpc_id(
		1,
		characters,
		gateway_id,
		peer_id
	)


@rpc("any_peer")
func receive_player_characters(_gateway_id: int, _peer_id: int, _player_characters: Dictionary) -> void:
	pass


@rpc("authority")
func request_login(
	gateway_id: int,
	peer_id: int,
	username: String,
	character_id: int
) -> void:
	var player: PlayerResource = database.get_player_resource(character_id)
	if player == null:
		return

	if player.account_name != username:
		return

	result_login.rpc_id(
		1,
		OK,
		gateway_id,
		peer_id,
		username,
		character_id,
	)


@rpc("any_peer")
func result_login(
	_result_code: int,
	_gateway_id: int,
	_peer_id: int,
	_username: String,
	_character_id: int
) -> void:
	pass
