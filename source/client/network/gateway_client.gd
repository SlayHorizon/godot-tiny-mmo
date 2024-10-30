extends Node


signal login_result_received(result: bool, message: String)
signal account_creation_result_received(result: bool, message: String)
signal player_character_creation_result_received(result: bool, message: String)
signal connection_changed(connected_to_server: bool)

# Server configuration.
## Server's adress. Use "127.0.0.1" or "localhost" to test locally.
const ADDRESS := "127.0.0.1" 
## The port the server listens to.
const PORT: int = 8088

var peer: WebSocketMultiplayerPeer
var peer_id: int

var is_connected_to_server: bool = false:
	set(value):
		is_connected_to_server = value
		connection_changed.emit(value)


func connect_to_gateway() -> void:
	print("Starting connection to the gateway server.")
	peer = WebSocketMultiplayerPeer.new()
	
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var certificate = load("res://test_config/server_certificate.crt")
	if certificate == null:
		print("Failed to load certificate.")
		return

	peer.create_client("wss://" + ADDRESS + ":" + str(PORT), TLSOptions.client_unsafe(certificate))
	multiplayer.set_multiplayer_peer(peer)


# Closes the active connection and resets the peer.
func close_connection() -> void:
	multiplayer.connected_to_server.disconnect(self._on_connection_succeeded)
	multiplayer.connection_failed.disconnect(self._on_connection_failed)
	multiplayer.server_disconnected.disconnect(self._on_server_disconnected)
	
	multiplayer.set_multiplayer_peer(null)
	peer.close()
	is_connected_to_server = false


func _on_connection_succeeded() -> void:
	print("Succesfuly connected to the gateway server as %d!" % multiplayer.get_unique_id())
	peer_id = multiplayer.get_unique_id()
	is_connected_to_server = true
	if OS.has_feature("debug"):
		DisplayServer.window_set_title("Gateway client - %d" % peer_id)


func _on_connection_failed() -> void:
	print("Failed to connect to the server.")
	close_connection()


func _on_server_disconnected() -> void:
	print("Server disconnected.")
	close_connection()
	get_tree().paused = true


@rpc("authority")
func fetch_authentication_token(_token: String, _adress: String, _port: int) -> void:
	close_connection()
	Client.authentication_token = _token
	Client.connect_to_server(_adress, _port)


@rpc("any_peer")
func login_request(_username: String, _password: String) -> void:
	pass


@rpc("authority")
func login_result(result_code: int) -> void:
	login_result_received.emit(result_code)


@rpc("any_peer")
func create_account_request(_username: String, _password: String, _is_guest: bool) -> void:
	pass


@rpc("authority")
func account_creation_result(result_code: int) -> void:
	account_creation_result_received.emit(result_code)


@rpc("any_peer")
func create_player_character_request(_character_data: Dictionary, _world_id: int) -> void:
	pass


@rpc("authority")
func player_character_creation_result(result_code: int) -> void:
	player_character_creation_result_received.emit(result_code)
