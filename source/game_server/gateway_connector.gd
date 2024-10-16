extends Node


signal token_received(token: String, player_data: Dictionary)

var adress := "127.0.0.1" 
var port: int = 8089
var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI


func connect_to_gateway() -> void:
	print("Starting connection to the Gateway as Game Server
	with adress %s and port %d." % [adress, port])
	
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
	print("Succesfuly connected to the Gateway as %d!" % multiplayer.get_unique_id())
	fetch_server_info.rpc_id(1, GameServer.port, "127.0.0.1")


func _on_connection_failed() -> void:
	print("Failed to connect to the Gateway as Game Server.")


func _on_server_disconnected() -> void:
	print("Game Server disconnected.")


@rpc("any_peer")
func fetch_server_info(_port: int, _adress: String) -> void:
	pass


@rpc("authority")
func fetch_token(token: String, player_data: Dictionary) -> void:
	token_received.emit(token, player_data)
