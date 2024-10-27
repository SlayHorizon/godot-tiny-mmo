extends Node


# Class Dependencies
const MasterServer: Script = preload("res://source/master_server/master_server.gd")

# Server Configuration
var port: int = 8062
var certificate_path := "res://source/common/server_certificate.crt"
var key_path := "res://source/common/server_key.key"

# Server Components
var master: MasterServer
var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI

# Active Connections
var connected_game_servers: Dictionary


func _ready() -> void:
	initialize_world_manager()


func _process(_delta: float) -> void:
	# Process multiplayer events if the API is active
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


# Initializes the World Manager server
func initialize_world_manager() -> void:
	load_server_configuration()
	setup_server_connection()


# Loads configuration from command-line arguments and optional config file
func load_server_configuration() -> void:
	var parsed_arguments := CmdlineUtils.get_parsed_args()
	print("Gateway parsed arguments = %s" % parsed_arguments)
	
	if parsed_arguments.has("port"):
		port = parsed_arguments["port"]
	
	if parsed_arguments.has("config"):
		var config_file := ConfigFile.new()
		var error := config_file.load(parsed_arguments["config"])
		if error != OK:
			printerr("Failed to load config at %s, error: %s" % [parsed_arguments["config"], error_string(error)])
		else:
			port = config_file.get_value("world-manager", "port", port)
			certificate_path = config_file.get_value("world-manager", "certificate_path", certificate_path)
			key_path = config_file.get_value("world-manager", "key_path", key_path)


# Sets up the WebSocket server and multiplayer API with TLS for secure connections
func setup_server_connection() -> void:
	var server_certificate: X509Certificate = load(certificate_path)
	var server_key: CryptoKey = load(key_path)
	if server_certificate == null or server_key == null:
		print("Certificate or key loading failed.")
		return
			
	print("Initializing World Manager Server.")
	custom_peer = WebSocketMultiplayerPeer.new()
	
	# Connect signals for managing peer connections
	custom_peer.peer_connected.connect(self._on_peer_connected)
	custom_peer.peer_disconnected.connect(self._on_peer_disconnected)
	
	# Create WebSocket server with TLS options for secure connections
	custom_peer.create_server(port, "*", TLSOptions.server(server_key, server_certificate))
	
	# Configure multiplayer API
	multiplayer_api = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(multiplayer_api, self.get_path()) 
	multiplayer_api.multiplayer_peer = custom_peer


func _on_peer_connected(peer_id: int) -> void:
	print("Gateway: %d is connected to GatewayManager." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Gateway: %d is disconnected to GatewayManager." % peer_id)


@rpc("any_peer")
func fetch_server_info(info: Dictionary) -> void:
	var game_server_id := multiplayer_api.get_remote_sender_id()
	connected_game_servers[game_server_id] = info


@rpc("authority")
func fetch_token(_token: String, _account_id: int) -> void:
	pass


@rpc("authority")
func create_player_character_request(_gateway_id: int, _peer_id: int, _account_id: int, _character_data: Dictionary) -> void:
	pass


@rpc("any_peer")
func player_character_creation_result(gateway_id: int, peer_id: int, account_id: int, result_code: int) -> void:
	var world_id := multiplayer_api.get_remote_sender_id()
	if result_code == OK:
		var token := master.authentication_manager.generate_random_token()
		fetch_token.rpc_id(world_id, token, account_id)
		master.gateway_manager.player_character_creation_result.rpc_id(
			gateway_id, peer_id, result_code
		)
		await get_tree().create_timer(0.5).timeout
		master.gateway_manager.fetch_authentication_token.rpc_id(
			gateway_id, peer_id, token, "127.0.0.1", 8087
		)
	else:
		master.gateway_manager.player_character_creation_result.rpc_id(
			gateway_id, peer_id, result_code
		)
