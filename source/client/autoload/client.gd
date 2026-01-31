extends BaseMultiplayerEndpoint


signal connection_changed(connected_to_server: bool)
signal authentication_requested

var peer_id: int
var is_connected_to_server: bool = false:
	set(value):
		is_connected_to_server = value
		connection_changed.emit(value)

var authentication_token: String

@onready var world_clock: WorldClock = $WorldClock


func _enter_tree() -> void:
	if not OS.has_feature("client"):
		queue_free()


func _ready() -> void:
	pass


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.connected_to_server.connect(_on_connection_succeeded)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)
	
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.peer_authentication_failed.connect(_on_peer_authentication_failed)
	api.set_auth_callback(authentication_call)


func connect_to_server(
	_address: String,
	_port: int,
	_authentication_token: String
) -> void:
	authentication_token = _authentication_token
	create(Role.CLIENT, _address, _port)


func close_connection() -> void:
	multiplayer.set_multiplayer_peer(null)
	peer.close()
	is_connected_to_server = false


func _on_connection_succeeded() -> void:
	print("Successfully connected to the server as %d!" % multiplayer.get_unique_id())
	peer_id = multiplayer.get_unique_id()
	is_connected_to_server = true

	if OS.has_feature("debug"):
		DisplayServer.window_set_title("Client - %d" % peer_id)


func _on_connection_failed() -> void:
	print("Failed to connect to the server.")
	close_connection()


func _on_server_disconnected() -> void:
	print("Server disconnected.")
	close_connection()
	get_tree().paused = true


func _on_peer_authenticating(_peer_id: int) -> void:
	print("Trying to authenticate to the server.")


func _on_peer_authentication_failed(_peer_id: int) -> void:
	print("Authentification to the server failed.")
	close_connection()


func authentication_call(_peer_id: int, data: PackedByteArray) -> void:
	print("Authentification call from server with data: \"%s\"." % data.get_string_from_ascii())
	multiplayer.send_auth(1, var_to_bytes(authentication_token))
	multiplayer.complete_auth(1)


var _next_data_request_id: int = 0
var _pending_data_requests: Dictionary[int, DataRequest]
var _data_subscriptions: Dictionary[StringName, Array]


func subscribe(type: StringName, callable: Callable) -> void:
	if _data_subscriptions.has(type) and not _data_subscriptions[type].has(callable):
		_data_subscriptions[type].append(callable)
	elif not _data_subscriptions.has(type):
		_data_subscriptions[type] = [callable]


func unsubscribe(type: StringName, callable: Callable) -> void:
	if not _data_subscriptions.has(type): return
	_data_subscriptions[type].erase(callable)


func cancel_request_data(request_id: int) -> bool:
	return _pending_data_requests.erase(request_id)


## Returns a array containing [Dictionary, DataRequest.Error]
func request_data_await(
	type: StringName,
	args: Dictionary = {},
	instance_id: String = ""
) -> Array:
	var request: DataRequest = request_data(type, Callable(), args, instance_id)
	var result = await request.finished

	return result


func request_data(
	type: StringName,
	callable: Callable = Callable(),
	args: Dictionary = {},
	instance_id: String = ""
) -> DataRequest:
	var request: DataRequest = DataRequest.new()
	var request_id = _next_data_request_id
	_next_data_request_id += 1

	request.request_id = request_id
	request.callable = callable
	_pending_data_requests[request_id] = request

	_data_request.rpc_id(1,
		request_id,
		type,
		args,
		instance_id
	)

	request.start_timeout(5.0)
	return request


@rpc("any_peer", "call_remote", "reliable", 1)
func _data_request(request_id: int, type: String, args: Dictionary, instance_id: String) -> void:
	# Server side
	pass


@rpc("authority", "call_remote", "reliable", 1)
func _data_response(request_id: int, type: String, data: Dictionary) -> void:
	if not _pending_data_requests.has(request_id): return
	
	var request: DataRequest = _pending_data_requests[request_id]
	_pending_data_requests.erase(request_id)

	if request.callable.is_valid():
		request.callable.call(data)
	request.finish(data)
	data_push(type, data)


@rpc("authority", "call_remote", "reliable", 1)
func data_push(type: String, data: Dictionary) -> void:
	for callable: Callable in _data_subscriptions.get(type, []):
		if callable.is_valid():
			callable.call(data)
		else:
			unsubscribe(type, callable)
