class_name BaseServer
extends Node


# Server Default Configuration / Set with load_server_configuration()
var port: int = 80443
var certificate_path := "res://test_config/tls/certificate.crt"
var key_path := "res://test_config/tls/key.key"

# Server Components
var server: WebSocketMultiplayerPeer
var multiplayer_api: MultiplayerAPI
var authentication_callback := Callable()


func _process(_delta: float) -> void:
	if multiplayer_api and multiplayer_api.has_multiplayer_peer():
		multiplayer_api.poll()


func init_multiplayer_api(use_default: bool = false) -> void:
	multiplayer_api = (
		MultiplayerAPI.create_default_interface()
		if not use_default else multiplayer
	)
	
	multiplayer_api.peer_connected.connect(_on_peer_connected)
	multiplayer_api.peer_disconnected.connect(_on_peer_disconnected)
	
	if authentication_callback:
		multiplayer_api.peer_authenticating.connect(_on_peer_authenticating)
		multiplayer_api.peer_authentication_failed.connect(_on_peer_authentication_failed)
		multiplayer_api.set_auth_callback(authentication_callback)
	
	get_tree().set_multiplayer(
		multiplayer_api,
		NodePath("") if use_default else get_path()
	)


func load_server_configuration(section_key: String, default_config_path: String = "") -> bool:
	var parsed_arguments := CmdlineUtils.get_parsed_args()
	
	var config_path := default_config_path
	var config_file := ConfigFile.new()
	if parsed_arguments.has("config"):
		config_path = parsed_arguments["config"]
	var error := config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at %s, error: %s" % [parsed_arguments["config"], error_string(error)])
	else:
		port = config_file.get_value(section_key, "port", port)
		certificate_path = config_file.get_value(section_key, "certificate_path", certificate_path)
		key_path = config_file.get_value(section_key, "key_path", key_path)
	return true


func start_server() -> void:
	if not multiplayer_api:
		init_multiplayer_api()
	
	server = WebSocketMultiplayerPeer.new()
	
	var tls_options := TLSOptionsUtils.create_server_tls_options(key_path, certificate_path)
	var error := server.create_server(port, "*", tls_options)
	if error != OK:
		printerr("Error while creating server: %s" % error_string(error))
	
	multiplayer_api.multiplayer_peer = server


func _on_peer_connected(peer_id: int) -> void:
	print("Peer: %d is connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer: %d is disconnected." % peer_id)


func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	multiplayer_api.send_auth(peer_id, "send_string".to_ascii_buffer())


func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)
