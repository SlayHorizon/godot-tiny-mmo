class_name WorldServer
extends BaseMultiplayerEndpoint
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

@export var database: WorldDatabase
@export var world_manager: WorldManagerClient
@export var world_clock: WorldClock
@export var chat_service: ChatService

var token_list: Dictionary[String, PlayerResource]

## {peer_id: PlayerResource}
var connected_players: Dictionary[int, PlayerResource]
## {player_id: peer_id}
var player_id_to_peer_id: Dictionary[int, int]

static var curr: WorldServer


func start_world_server() -> void:
	world_manager.token_received.connect(
		func(auth_token: String, _username: String, character_id: int):
			var player: PlayerResource = database.get_player_resource(character_id)
			token_list[auth_token] = player
	)

	var configuration: Dictionary = ConfigFileUtils.load_section(
		"world-server",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/world_config.cfg")
	)
	if configuration.has("error"):
		# Error case
		pass
	else:
		create(Role.SERVER, configuration.bind_address, configuration.port)

	chat_service.setup_with_db(database.db)
	$InstanceManager.start_instance_manager()


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.peer_authentication_failed.connect(_on_peer_authentication_failed)
	api.set_auth_callback(_authentication_callback)


func _on_peer_connected(peer_id: int) -> void:
	print("Peer: %d is connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer: %d is disconnected." % peer_id)
	world_manager.player_disconnected.rpc_id(1, connected_players[peer_id].account_name)
	var player: PlayerResource = connected_players.get(peer_id)
	if not player:
		return

	database.save_player(player)

	player_id_to_peer_id.erase(player.player_id)

	player.current_peer_id = 0
	connected_players.erase(peer_id)


func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	multiplayer.send_auth(peer_id, "data_from_server".to_ascii_buffer())


func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)


func _authentication_callback(peer_id: int, data: PackedByteArray) -> void:
	var auth_token := bytes_to_var(data) as String
	print("Peer: %d is trying to connect with data: \"%s\"." % [peer_id, auth_token])
	if is_valid_authentication_token(auth_token):
		multiplayer.complete_auth(peer_id)
		connected_players[peer_id] = token_list[auth_token]
		connected_players[peer_id].current_peer_id = peer_id
		player_id_to_peer_id[connected_players[peer_id].player_id] = peer_id
		token_list.erase(auth_token)
	else:
		peer.disconnect_peer(peer_id)


func is_valid_authentication_token(auth_token: String) -> bool:
	if token_list.has(auth_token):
		return true
	return false


@export var instance_manager: InstanceManagerServer

var data_handlers: Dictionary[StringName, DataRequestHandler]


func _ready() -> void:
	curr = self


## If no instance_id is provided, will use all peers connected in the world.
func propagate_rpc(callable: Callable, instance_id: String = "") -> void:
	var instance: ServerInstance = instance_manager.get_instance_server_by_id(instance_id)
	if instance:
		for peer_id: int in instance.connected_peers:
			callable.rpc_id(peer_id)
	else:
		for peer_id: int in instance_manager.world_server.connected_players:
			callable.rpc_id(peer_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _data_request(
	request_id: int,
	type: StringName,
	args: Dictionary = {},
	instance_id: String = ""
) -> void:
	const DATA_REQUEST_HANDLERS_PATH: String = "res://source/server/world/components/data_request_handlers/"
	var peer_id: int = multiplayer.get_remote_sender_id()
	var instance: ServerInstance = instance_manager.get_instance_server_by_id(instance_id)

	if not instance:
		instance = instance_manager.default_instance.charged_instances[0]

	if not data_handlers.has(type):
		var path: String = DATA_REQUEST_HANDLERS_PATH + type + ".gd"
		if not ResourceLoader.exists(path):
			return
		var script: GDScript = load(path)
		if not script:
			return

		var handler = script.new() as DataRequestHandler
		if not handler:
			return
		data_handlers[type] = handler

	_data_response.rpc_id(
		peer_id,
		request_id,
		type,
		data_handlers[type].data_request_handler(peer_id, instance, args)
	)


@rpc("authority", "call_remote", "reliable", 1)
func _data_response(request_id: int, type: String, data: Dictionary) -> void:
	# Client only
	pass


@rpc("authority", "call_remote", "reliable", 1)
func data_push(type: StringName, data: Dictionary) -> void:
	# Client only
	pass
