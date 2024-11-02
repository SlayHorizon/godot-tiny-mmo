extends CustomServer
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

# Loading classes
const MasterClient: Script = preload("res://source/world_server/master_client.gd")

# References
var master_client: MasterClient

# {token: {"username": "salade", "class": "knight"}}
var token_list: Dictionary
var player_list: Dictionary
var characters: Dictionary
var next_id: int = 0


func _ready() -> void:
	load_server_configuration("world-server", "res://test_config/world_server_config.cfg")
	authentication_callback = _authentication_callback
	start_server()
	add_master_client.call_deferred()


func init_multiplayer_api() -> void:
	multiplayer_api = MultiplayerAPI.create_default_interface()
	
	multiplayer_api.peer_connected.connect(_on_peer_connected)
	multiplayer_api.peer_disconnected.connect(_on_peer_disconnected)
	
	if authentication_callback:
		multiplayer_api.peer_authenticating.connect(_on_peer_authenticating)
		multiplayer_api.peer_authentication_failed.connect(_on_peer_authentication_failed)
		multiplayer_api.set_auth_callback(authentication_callback)
	
	get_tree().set_multiplayer(multiplayer_api)


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


func add_master_client() -> void:
	master_client = MasterClient.new()
	master_client.name = "WorldManager"
	master_client.token_received.connect(
		func(token: String, account_id: int):
			token_list[token] = account_id
	)
	master_client.world_server = self
	add_sibling(master_client)
