extends Node


# Class Dependencies
const MasterServer: Script = preload("res://source/master_server/master_server.gd")

# Server Default Configuration
var port: int = 8062
var certificate_path := "res://source/common/server_certificate.crt"
var key_path := "res://source/common/server_key.key"

# Loaded server assets
var server_certificate: X509Certificate
var server_key: CryptoKey

# Server Components
var master: MasterServer
var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI

# Active Connections
var connected_game_servers: Dictionary


func _ready() -> void:
	if load_server_configuration("world-manager"):
		print("Starting WorldManager on port %d" % port)
		start_server()

 
func _process(_delta: float) -> void:
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


# Parses command-line arguments, loads configuration settings, and loads certificate/key files
func load_server_configuration(section_key: String) -> bool:
	var parsed_arguments := CmdlineUtils.get_parsed_args()
	print("Parsed arguments: %s" % parsed_arguments)
	
	# Load configuration from specified config file if available
	if parsed_arguments.has("config"):
		var config_file := ConfigFile.new()
		var error := config_file.load(parsed_arguments["config"])
		if error != OK:
			printerr("Failed to load config at %s, error: %s" % [parsed_arguments["config"], error_string(error)])
		else:
			port = config_file.get_value(section_key, "port", port)
			certificate_path = config_file.get_value(section_key, "certificate_path", certificate_path)
			key_path = config_file.get_value(section_key, "key_path", key_path)
	
	# Load server certificate and key for TLS connection
	server_certificate = load(certificate_path)
	server_key = load(key_path)
	
	# Validate loaded assets
	if server_certificate == null or server_key == null:
		printerr("Failed to load certificate or key. Check paths: %s, %s" % [certificate_path, key_path])
		return false
	return true


# Initializes and starts the WebSocket server with the preloaded parameters
func start_server() -> void:
	custom_peer = WebSocketMultiplayerPeer.new()
	
	# Connect peer signals
	custom_peer.peer_connected.connect(self._on_peer_connected)
	custom_peer.peer_disconnected.connect(self._on_peer_disconnected)
	
	# Create WebSocket server with TLS options
	custom_peer.create_server(port, "*", TLSOptions.server(server_key, server_certificate))
	
	# Set up multiplayer API with the custom peer
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
