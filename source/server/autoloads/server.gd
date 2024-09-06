extends Node
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

const PORT: int = 8087

var peer: WebSocketMultiplayerPeer

var player_list: Dictionary

## For autocomplention
@onready var scene_multiplayer := multiplayer as SceneMultiplayer

func start_server() -> void:
	print("Starting server.")
	peer = WebSocketMultiplayerPeer.new()
	
	multiplayer.peer_connected.connect(self._on_peer_connected)
	multiplayer.peer_disconnected.connect(self._on_peer_disconnected)
	
	scene_multiplayer.peer_authenticating.connect(self._on_peer_authenticating)
	scene_multiplayer.peer_authentication_failed.connect(self._on_peer_authentication_failed)
	scene_multiplayer.set_auth_callback(self.authentication_call)
	
	var server_certificate = load("res://source/common/server_certificate.crt")
	var server_key = load("res://source/server/server_key.key")
	if server_certificate == null or server_key == null:
		print("Failed to load certificate or key.")
		return
	
	peer.create_server(PORT, "*", TLSOptions.server(server_key, server_certificate))
	multiplayer.set_multiplayer_peer(peer)

func _on_peer_connected(peer_id) -> void:
	print("Peer: %d is connected." % peer_id)

func _on_peer_disconnected(peer_id) -> void:
	print("Peer: %d is disconnected." % peer_id)
	player_list.erase(peer_id)

func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	scene_multiplayer.send_auth(peer_id, "data_from_server".to_ascii_buffer())

func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)

# Quick and dirty, needs rework.
func authentication_call(peer_id: int, data: PackedByteArray) -> void:
	var dict := bytes_to_var(data) as Dictionary
	print("Peer: %d is trying to connect with data: \"%s\"." % [peer_id, dict])
	if is_valid_authentication_data(dict):
		scene_multiplayer.complete_auth(peer_id)
		player_list[peer_id] = dict
	else:
		peer.disconnect_peer(peer_id)

func is_valid_authentication_data(data: Dictionary) -> bool:
	var player_name: String
	var player_class: String
	if data.has("username") and data.has("class"):
		player_name = data["username"] as String
		player_class = data["class"] as String
	else:
		return false
	if not player_name.is_valid_identifier() or not player_name.length() < 10:
		return false
	elif not player_class in ["knight", "rogue", "wizard"]:
		return false
	return true
