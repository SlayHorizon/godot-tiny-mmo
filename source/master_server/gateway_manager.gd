extends Node


# Class Dependencies
const MasterServer: Script = preload("res://source/master_server/master_server.gd")

# Server Default Configuration
var port: int = 8044
var certificate_path := "res://source/common/server_certificate.crt"
var key_path := "res://source/common/server_key.key"

# Loaded server assets
var server_certificate: X509Certificate
var server_key: CryptoKey

# Server Components
var master: MasterServer
var custom_peer: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI


func _ready() -> void:
	if load_server_configuration("gateway-manager"):
		print("Starting GatewayManager on port %d" % port)
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
	var error := custom_peer.create_server(port, "*", TLSOptions.server(server_key, server_certificate))
	if error != OK:
		printerr(error_string(error))
	# Set up multiplayer API with the custom peer
	multiplayer_api = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(multiplayer_api, self.get_path())
	multiplayer_api.multiplayer_peer = custom_peer


func _on_peer_connected(peer_id: int) -> void:
	print("Gateway: %d is connected to GatewayManager." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Gateway: %d is disconnected to GatewayManager." % peer_id)


# Send the game servers info the the gateway (server name, population etc.)
#@rpc("authority")
#func fetch_servers_info(_info: Dictionary) -> void:
	#pass


# Send an authentication token to the gateway for a specific peer,
# used by the peer to connect to a game server.
@rpc("authority")
func fetch_authentication_token(_target_peer: int, _token: String, _adress: String, _port: int) -> void:
	pass


#@rpc("any_peer")
#func login_request(user_id: int, username: String, password: String) -> void:
	#var gateway_id := multiplayer_api.get_remote_sender_id()
	#var result := master.authentication_manager.database.validate_credentials(username, password)
	#login_result.rpc_id(gateway_id, user_id, result)
#
#
#@rpc("authority")
#func login_result(_user_id: int, _result_code: int) -> void:
	#pass


@rpc("any_peer")
func create_account_request(peer_id: int, username: String, password: String, is_guest: bool) -> void:
	var gateway_id := multiplayer_api.get_remote_sender_id()
	var result_code: int = 0
	var return_data := {}
	var result := master.authentication_manager.create_accout(username, password, is_guest)
	if result == null:
		result_code = 30
	else:
		return_data = {"name": result.username, "id": result.id}
		
	account_creation_result.rpc_id(gateway_id, peer_id, result_code, return_data)


@rpc("authority")
func account_creation_result(_peer_id: int, _result_code: int, _data: Dictionary) -> void:
	pass


# Used to create the player's character.
@rpc("any_peer")
func create_player_character_request(world_id: int, peer_id: int, account_id: int, character_data: Dictionary) -> void:
	var gateway_id := multiplayer_api.get_remote_sender_id()
	master.world_manager.create_player_character_request.rpc_id(
		master.world_manager.connected_game_servers.keys()[world_id],
		gateway_id, peer_id, account_id, character_data
	)


@rpc("authority")
func player_character_creation_result(_peer_id: int, _result_code: int) -> void:
	pass
