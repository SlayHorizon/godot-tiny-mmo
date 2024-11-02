extends CustomServer


# Class Dependencies
const MasterServer: Script = preload("res://source/master_server/master_server.gd")

# Server Components
var master: MasterServer


func _ready() -> void:
	load_server_configuration("gateway-manager", "res://test_config/master_server_config.cfg")
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


#@rpc("any_peer")
#func login_request(user_id: int, username: String, password: String) -> void:
	#var gateway_id := multiplayer_api.get_remote_sender_id()
	#var result := master.authentication_manager.database.validate_credentials(username, password)
	#login_result.rpc_id(gateway_id, user_id, result)
#
#
#@rpc("authority")
#func login_result(_user_id: int, _result_code: int) -> void:
	#pass


@rpc("any_peer")
func create_account_request(peer_id: int, username: String, password: String, is_guest: bool) -> void:
	var gateway_id := multiplayer_api.get_remote_sender_id()
	var result_code: int = 0
	var return_data := {}
	var result := master.authentication_manager.create_accout(username, password, is_guest)
	if result == null:
		result_code = 30
	else:
		return_data = {"name": result.username, "id": result.id}
		
	account_creation_result.rpc_id(gateway_id, peer_id, result_code, return_data)


@rpc("authority")
func account_creation_result(_peer_id: int, _result_code: int, _data: Dictionary) -> void:
	pass


# Used to create the player's character.
@rpc("any_peer")
func create_player_character_request(world_id: int, peer_id: int, account_id: int, character_data: Dictionary) -> void:
	var gateway_id := multiplayer_api.get_remote_sender_id()
	master.world_manager.create_player_character_request.rpc_id(
		master.world_manager.connected_game_servers.keys()[world_id],
		gateway_id, peer_id, account_id, character_data
	)


@rpc("authority")
func player_character_creation_result(_peer_id: int, _result_code: int) -> void:
	pass
