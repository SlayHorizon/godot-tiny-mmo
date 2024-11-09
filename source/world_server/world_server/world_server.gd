class_name WorldServer
extends BaseServer
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

@export var world_manager: WorldManagerClient

# {token_code: {"username": "salade", "class": "knight"}}
var token_list: Dictionary
var player_list: Dictionary
var characters: Dictionary
var next_id: int = 0


func _ready() -> void:
	world_manager.token_received.connect(
		func(token: String, account_id: int):
			token_list[token] = account_id
	)
	authentication_callback = _authentication_callback
	load_server_configuration("world-server", "res://test_config/world_server_config.cfg")
	start_server()


func _on_peer_connected(peer_id: int) -> void:
	print("Peer: %d is connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer: %d is disconnected." % peer_id)
	player_list.erase(peer_id)


func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	multiplayer.send_auth(peer_id, "data_from_server".to_ascii_buffer())


func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)


# Quick and dirty, needs rework.
func _authentication_callback(peer_id: int, data: PackedByteArray) -> void:
	#var dict := bytes_to_var(data) as Dictionary
	var token := bytes_to_var(data) as String
	print("Peer: %d is trying to connect with data: \"%s\"." % [peer_id, token])
	if is_valid_authentication_token(token):
		multiplayer.complete_auth(peer_id)
		#player_list[peer_id] = dict
		player_list[peer_id] = characters[token_list[token]]
		token_list.erase(token)
	else:
		server.disconnect_peer(peer_id)


func is_valid_authentication_token(token: String) -> bool:
	if token_list.has(token):
		return true
	return false
