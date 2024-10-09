extends Node


signal connection_changed(connected_to_server: bool)

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


func connect_to_server() -> void:
	print("Starting connection to the gateway server.")
	peer = WebSocketMultiplayerPeer.new()
	
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var certificate = load("res://source/common/server_certificate.crt")
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
