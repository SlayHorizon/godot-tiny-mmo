class_name WorldServer
extends BaseServer
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

@export var database: WorldDatabase
@export var world_manager: WorldManagerClient

# {token_code: {"username": "salade", "class": "knight"}}
var token_list: Dictionary

var connected_players: Dictionary


func _ready() -> void:
	world_manager.token_received.connect(
		func(token: String, _username: String, character_id: int):
			var player: PlayerResource = database.player_data.get_player_resource(character_id)
			token_list[token] = player
	)
	authentication_callback = _authentication_callback
	load_server_configuration("world-server", "res://test_config/world_server_config.cfg")
	start_server()


func _on_peer_connected(peer_id: int) -> void:
	print("Peer: %d is connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer: %d is disconnected." % peer_id)
	world_manager.player_disconnected.rpc_id(
		1, connected_players[peer_id].account_name
	)
	connected_players.erase(peer_id)


func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	multiplayer.send_auth(peer_id, "data_from_server".to_ascii_buffer())


func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)


func _authentication_callback(peer_id: int, data: PackedByteArray) -> void:
	var token := bytes_to_var(data) as String
	print("Peer: %d is trying to connect with data: \"%s\"." % [peer_id, token])
	if is_valid_authentication_token(token):
		multiplayer.complete_auth(peer_id)
		connected_players[peer_id] = token_list[token]
		token_list.erase(token)
	else:
		server.disconnect_peer(peer_id)


func is_valid_authentication_token(token: String) -> bool:
	if token_list.has(token):
		return true
	return false
