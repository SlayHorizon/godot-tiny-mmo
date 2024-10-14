extends Node


const PORT: int = 8089

var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI
var game_server_list: Array[int]

func _process(_delta: float) -> void:
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


func start_game_server_listener() -> void:
	print("Starting connection to the game server.")
	custom_peer = WebSocketMultiplayerPeer.new()
	
	custom_peer.peer_connected.connect(self._on_peer_connected)
	custom_peer.peer_disconnected.connect(self._on_peer_disconnected)
	
	var server_certificate = load("res://source/common/server_certificate.crt")
	var server_key = load("res://source/game_server/server_key.key")
	if server_certificate == null or server_key == null:
		print("Failed to load certificate or key.")
		return
	
	custom_peer.create_server(PORT, "*", TLSOptions.server(server_key, server_certificate))
	multiplayer_api = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(multiplayer_api, self.get_path()) 
	multiplayer_api.multiplayer_peer = custom_peer


func _on_peer_connected(peer_id: int) -> void:
	print("Game Server: %d is connected to Gateway." % peer_id)
	game_server_list.append(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	game_server_list.erase(peer_id)
	print("Game Server: %d is disconnected from Gateway." % peer_id)

@rpc("authority")
func fetch_token(_token: String, _player_data: Dictionary) -> void:
	pass
