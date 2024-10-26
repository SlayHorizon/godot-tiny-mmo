extends Node


# Loading classes 
const MasterServer: Script = preload("res://source/master_server/master_server.gd")

# Configuration
var port: int = 8064

# References
var master: MasterServer
var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI


func _ready() -> void:
	start_gateway_manager()


func _process(_delta: float) -> void:
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


func start_gateway_manager() -> void:
	print("Starting Gateway Manager server.")
	custom_peer = WebSocketMultiplayerPeer.new()
	
	custom_peer.peer_connected.connect(self._on_peer_connected)
	custom_peer.peer_disconnected.connect(self._on_peer_disconnected)
	
	var server_certificate = load("res://source/common/server_certificate.crt")
	var server_key = load("res://source/common/server_key.key")
	if server_certificate == null or server_key == null:
		print("Failed to load certificate or key.")
		return
	
	custom_peer.create_server(port, "*", TLSOptions.server(server_key, server_certificate))
	multiplayer_api = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(multiplayer_api, self.get_path()) 
	multiplayer_api.multiplayer_peer = custom_peer


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
