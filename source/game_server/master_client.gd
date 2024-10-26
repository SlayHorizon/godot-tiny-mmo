extends Node


# Loading classes 
const WorldServer = preload("res://source/game_server/autoloads/game_server.gd")

signal token_received(token: String, player_data: Dictionary)

# Configuration
var port: int = 8062
var adress := "127.0.0.1"

var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI
var game_server_list: Dictionary
var world_server: WorldServer


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


func start_master_client() -> void:
	print("Starting connection to the Master Server as Gateway Server.")
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
	fetch_server_info.rpc_id(
		1,
		{
			"port": world_server.port,
			"adress": "127.0.0.1",
			"rules": "None",
			"population": world_server.player_list.size()
		}
		)


func _on_connection_failed() -> void:
	print("Failed to connect to the Gateway as Game Server.")


func _on_server_disconnected() -> void:
	print("Game Server disconnected.")


@rpc("any_peer")
func fetch_server_info(_info: Dictionary) -> void:
	pass


@rpc("authority")
func fetch_token(token: String, account_id: int) -> void:
	token_received.emit(token, account_id)


@rpc("authority")
func create_player_character_request(gateway_id: int, peer_id: int, account_id: int, character_data: Dictionary) -> void:
	if world_server.characters.has(account_id) and world_server.characters[account_id].size()  > 3: #max character per account
		player_character_creation_result.rpc_id(1, gateway_id, peer_id, account_id, 22)
		return
	world_server.characters[account_id] = {world_server.next_id: character_data}
	world_server.next_id += 1
	player_character_creation_result.rpc_id(1, gateway_id, peer_id, account_id, 0)


@rpc("any_peer")
func player_character_creation_result(_gateway_id: int, _peer_id: int, _account_id: int, _result_code: int) -> void:
	pass
