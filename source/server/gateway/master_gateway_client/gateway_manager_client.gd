class_name GatewayManagerClient
extends BaseMultiplayerEndpoint


signal account_creation_result_received(user_id: int, result_code: int, data: Dictionary)
signal login_succeeded(account_info: Dictionary, _worlds_info: Dictionary)
signal response_received(request_id: int, response: Dictionary)

var worlds_info: Dictionary


func _ready() -> void:
	var configuration: Dictionary = ConfigFileUtils.load_section(
		"gateway-manager-client",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/gateway_config.cfg")
	)
	create(Role.CLIENT, configuration.address, configuration.port)


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.connected_to_server.connect(_on_connection_succeeded)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)


func _on_connection_succeeded() -> void:
	print("Successfully connected to the Gateway Manager as %d!" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	print("Failed to connect to the Gateway Manager as Gateway.")
	# Try to reconnect.
	get_tree().create_timer(15.0).timeout.connect(_ready)


func _on_server_disconnected() -> void:
	print("Gateway Manager disconnected.")
	# Try to reconnect.
	get_tree().create_timer(15.0).timeout.connect(_ready)


@rpc("any_peer", "call_remote")
func gateway_request(request_id: int, request: Dictionary) -> void:
	pass


@rpc("authority", "call_remote")
func gateway_response(request_id: int, response: Dictionary) -> void:
	var gateway = $"../GatewayHTTPServer"
	var request: NetRequest = gateway.pending_requests.get(request_id)
	if request:
		request.resolve(response)


@rpc("authority")
func update_worlds_info(_worlds_info: Dictionary) -> void:
	worlds_info = _worlds_info
