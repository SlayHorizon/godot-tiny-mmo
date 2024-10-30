extends Node
## Client autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

signal connection_changed(connected_to_server: bool)
signal authentication_requested

# Server configuration.
## Server's adress. Use "127.0.0.1" or "localhost" to test locally.
const ADDRESS := "127.0.0.1" 
## The port the server listens to.
const PORT: int = 8087

var peer: WebSocketMultiplayerPeer
var peer_id: int

var is_connected_to_server: bool = false:
	set(value):
		is_connected_to_server = value
		connection_changed.emit(value)

#var authentication_data := {"username": "Player", "class": "knight"}
var authentication_token: String

## For autocomplention
@onready var scene_multiplayer := multiplayer as SceneMultiplayer


func connect_to_server(adress: String, port: int) -> void:
	print("Starting connection to the game server.")
	peer = WebSocketMultiplayerPeer.new()
	
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	scene_multiplayer.peer_authenticating.connect(self._on_peer_authenticating)
	scene_multiplayer.peer_authentication_failed.connect(self._on_peer_authentication_failed)
	scene_multiplayer.set_auth_callback(authentication_call)
	
	var certificate = load("res://test_config/server_certificate.crt")
	if certificate == null:
		print("Failed to load certificate.")
		return

	peer.create_client("wss://" + adress + ":" + str(port), TLSOptions.client_unsafe(certificate))
	multiplayer.set_multiplayer_peer(peer)


# Closes the active connection and resets the peer.
func close_connection() -> void:
	multiplayer.connected_to_server.disconnect(self._on_connection_succeeded)
	multiplayer.connection_failed.disconnect(self._on_connection_failed)
	multiplayer.server_disconnected.disconnect(self._on_server_disconnected)
	
	scene_multiplayer.peer_authenticating.disconnect(self._on_peer_authenticating)
	scene_multiplayer.peer_authentication_failed.disconnect(self._on_peer_authentication_failed)
	
	multiplayer.set_multiplayer_peer(null)
	peer.close()
	is_connected_to_server = false


func _on_connection_succeeded() -> void:
	print("Succesfuly connected to the server as %d!" % multiplayer.get_unique_id())
	peer_id = multiplayer.get_unique_id()
	is_connected_to_server = true
	if OS.has_feature("debug"):
		DisplayServer.window_set_title("Client - %d" % peer_id)


func _on_connection_failed() -> void:
	print("Failed to connect to the server.")
	close_connection()


func _on_server_disconnected() -> void:
	print("Server disconnected.")
	close_connection()
	get_tree().paused = true


func _on_peer_authenticating(_peer_id: int) -> void:
	print("Trying to authenticate to the server.")


func _on_peer_authentication_failed(_peer_id: int) -> void:
	print("Authentification to the server failed.")
	close_connection()


func authentication_call(_peer_id: int, data: PackedByteArray) -> void:
	print("Authentification call from server with data: \"%s\"." % data.get_string_from_ascii())
	scene_multiplayer.send_auth(1, var_to_bytes(authentication_token))
	scene_multiplayer.complete_auth(1)
