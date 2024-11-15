class_name WorldClient
extends BaseClient


signal connection_changed(connected_to_server: bool)
signal authentication_requested

var peer_id: int
var is_connected_to_server: bool = false:
	set(value):
		is_connected_to_server = value
		connection_changed.emit(value)

var authentication_token: String


func connect_to_server(_address: String, _port: int) -> void:
	address = _address
	port = _port
	authentication_callback = authentication_call
	start_client()


func close_connection() -> void:
	multiplayer.set_multiplayer_peer(null)
	client.close()
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
	multiplayer.send_auth(1, var_to_bytes(authentication_token))
	multiplayer.complete_auth(1)
