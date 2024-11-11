class_name GatewayManagerServer
extends BaseServer


@export var world_manager: WorldManagerServer
@export var authentication_manager: AuthenticationManager
@export var database: MasterDatabase


func _ready() -> void:
	load_server_configuration("gateway-manager-server", "res://test_config/master_server_config.cfg")
	start_server()


func _on_peer_connected(peer_id: int) -> void:
	print("Gateway: %d is connected to GatewayManager." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Gateway: %d is disconnected to GatewayManager." % peer_id)


# Send the game servers info the the gateway (server name, population etc.)
#@rpc("authority")
#func fetch_servers_info(_info: Dictionary) -> void:
	#pass


# Send an authentication token to the gateway for a specific peer,
# used by the peer to connect to a game server.
@rpc("authority")
func fetch_authentication_token(_target_peer: int, _token: String, _adress: String, _port: int) -> void:
	pass


@rpc("any_peer")
func login_request(peer_id: int, username: String, password: String) -> void:
	var gateway_id := multiplayer.get_remote_sender_id()
	var account: AccountResource = database.validate_credentials(
		username, password
	)
	if not account:
		login_result.rpc_id(gateway_id, peer_id, {"error": 50})
	elif account.is_online:
		login_result.rpc_id(gateway_id, peer_id, {"error": 51})
	else:
		account.is_online = true
		login_result.rpc_id(
			gateway_id, peer_id,
			{"name": account.username, "id": account.id}
		)


@rpc("authority")
func login_result(_peer_id: int, _result: Dictionary) -> void:
	pass



@rpc("any_peer")
func create_account_request(peer_id: int, username: String, password: String, is_guest: bool) -> void:
	var gateway_id := multiplayer_api.get_remote_sender_id()
	var result_code: int = 0
	var return_data := {}
	var result := authentication_manager.create_accout(username, password, is_guest)
	if result == null:
		result_code = 30
	else:
		return_data = {"name": result.username, "id": result.id}
		result.is_online = true
	account_creation_result.rpc_id(gateway_id, peer_id, result_code, return_data)


@rpc("authority")
func account_creation_result(_peer_id: int, _result_code: int, _data: Dictionary) -> void:
	pass


# Used to create the player's character.
@rpc("any_peer")
func create_player_character_request(world_id: int, peer_id: int, account_id: int, character_data: Dictionary) -> void:
	var gateway_id := multiplayer_api.get_remote_sender_id()
	# Verification if the peer_id is verified
	world_manager.create_player_character_request.rpc_id(
		world_manager.connected_game_servers.keys()[world_id],
		gateway_id, peer_id, account_id, character_data
	)


@rpc("authority")
func player_character_creation_result(_peer_id: int, _result_code: int) -> void:
	pass
