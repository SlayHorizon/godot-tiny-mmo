extends Node


# Loading classes 
const GatewayServer = preload("res://source/gateway_server/gateway_server.gd")

signal account_creation_result_received(user_id: int, result_code: int, data: Dictionary)

# Configuration
var port: int = 8064
var adress := "127.0.0.1"

# References
var gateway: GatewayServer
var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI

var game_server_list: Dictionary


func _ready() -> void:
	await get_tree().create_timer(1.5).timeout
	start_master_client.call_deferred()


func _process(_delta: float) -> void:
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


func start_master_client() -> void:
	print("Starting connection to the Master Server as Gateway Server.")
	custom_peer = WebSocketMultiplayerPeer.new()
	
	var certificate := load("res://source/common/server_certificate.crt")
	if certificate == null:
		print("Failed to load certificate.")
		return
	
	var error := custom_peer.create_client("wss://" + adress + ":" + str(port), TLSOptions.client_unsafe(certificate))
	if error:
		print(error_string(error))
		return
	
	multiplayer_api = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(multiplayer_api, self.get_path()) 
	multiplayer_api.multiplayer_peer = custom_peer
	
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_connection_succeeded() -> void:
	print("Succesfuly connected to the Gateway Manager as %d!" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	print("Failed to connect to the Gateway Manager as Gateway.")


func _on_server_disconnected() -> void:
	print("Gateway Manager disconnected.")


@rpc("authority")
func fetch_authentication_token(target_peer: int, token: String, _adress: String, _port: int) -> void:
	gateway.fetch_authentication_token.rpc_id(target_peer, token, _adress, _port)


@rpc("any_peer")
func create_account_request(_peer_id: int, _username: String, _password: String, _is_guest: bool) -> void:
	pass


@rpc("authority")
func account_creation_result(peer_id: int, result_code: int, data: Dictionary) -> void:
	account_creation_result_received.emit(peer_id, result_code, data)


@rpc("any_peer")
func create_player_character_request(_peer_id: int , _account_id: int, _character_data: Dictionary, _world_id: int) -> void:
	pass


@rpc("authority")
func player_character_creation_result(peer_id: int, result_code: int) -> void:
	gateway.player_character_creation_result.rpc_id(
		peer_id, result_code
	)
