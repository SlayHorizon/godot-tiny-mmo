class_name CustomClient
extends Node


# Client Configuration / Set with load_server_configuration()
var adress := "127.0.0.1"
var port: int = 8043
var certificate_path := "res://test_config/tls/certificate.crt"

# Server Components
var client: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI
var authentication_callback := Callable()


func _process(_delta: float) -> void:
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


func init_multiplayer_api() -> void:
	multiplayer_api = MultiplayerAPI.create_default_interface()
	
	multiplayer_api.connected_to_server.connect(_on_connection_succeeded)
	multiplayer_api.connection_failed.connect(_on_connection_failed)
	multiplayer_api.server_disconnected.connect(_on_server_disconnected)
	
	if authentication_callback:
		multiplayer_api.peer_authenticating.connect(_on_peer_authenticating)
		multiplayer_api.peer_authentication_failed.connect(_on_peer_authentication_failed)
		multiplayer_api.set_auth_callback(authentication_callback)
	
	get_tree().set_multiplayer(multiplayer_api, get_path())


func load_client_configuration(section_key: String, default_config_path: String = "") -> bool:
	var parsed_arguments := CmdlineUtils.get_parsed_args()
	
	var config_path := default_config_path
	var config_file := ConfigFile.new()
	if parsed_arguments.has("config"):
		config_path = parsed_arguments["config"]
	var error := config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at %s, error: %s" % [parsed_arguments["config"], error_string(error)])
	else:
		adress = config_file.get_value(section_key, "key_path", adress)
		port = config_file.get_value(section_key, "port", port)
		certificate_path = config_file.get_value(section_key, "certificate_path", certificate_path)
	return true


func start_client() -> void:
	if not multiplayer_api:
		init_multiplayer_api()
	
	client = WebSocketMultiplayerPeer.new()
	
	var tls_options := TLSOptionsUtils.create_client_tls_options(certificate_path)
	var error := client.create_client("wss://" + adress + ":" + str(port), tls_options)
	if error != OK:
		printerr("Error while creating client: %s" % error_string(error))
	
	multiplayer_api.multiplayer_peer = client


func _on_connection_succeeded() -> void:
	print("Succesfuly connected as %d!" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	print("Failed to connect to the server.")


func _on_server_disconnected() -> void:
	print("Server disconnected.")


func _on_peer_authenticating(_peer_id: int) -> void:
	print("Trying to authenticate.")


func _on_peer_authentication_failed(_peer_id: int) -> void:
	print("Authentification failed.")
