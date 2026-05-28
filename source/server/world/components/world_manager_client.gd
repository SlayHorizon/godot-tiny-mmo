class_name WorldManagerClient
extends BaseMultiplayerEndpoint


signal token_received(auth_token: String, username: String, character_id: int)

@export var database: WorldDatabase
@export var world_server: WorldServer

var world_info: Dictionary


func start_client_to_master_server(_world_info: Dictionary) -> void:
	
	world_info = _world_info
	var configuration: Dictionary = ConfigFileUtils.load_section(
		"world-manager-client",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/world_config.cfg")
	)
	create(Role.CLIENT, configuration.address, configuration.port)


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.connected_to_server.connect(_on_connection_succeeded)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)


func _on_connection_succeeded() -> void:
	print("Successfully connected to the Gateway as %d!" % multiplayer.get_unique_id())
	fetch_server_info.rpc_id(
		1,
		{
			"port": world_info.port,
			"address": "127.0.0.1",
			"info": world_info,
			"population": world_server.connected_players.size()
		}
	)
	# Start the heartbeat once we're attached. Master uses it to drive the
	# dashboard's live "online players / instances" columns and to know whether
	# a world is still responsive.
	_start_heartbeat()


## Push a fresh snapshot to the master every HEARTBEAT_SECONDS so the dashboard
## shows live numbers without each request hitting every world directly.
const HEARTBEAT_SECONDS: float = 10.0

func _start_heartbeat() -> void:
	if has_node(^"HeartbeatTimer"):
		return
	var t: Timer = Timer.new()
	t.name = "HeartbeatTimer"
	t.wait_time = HEARTBEAT_SECONDS
	t.autostart = true
	t.timeout.connect(_send_heartbeat)
	add_child(t)
	# Send one immediately so the master has data before the first tick.
	_send_heartbeat()


func _send_heartbeat() -> void:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	heartbeat.rpc_id(1, _build_snapshot())


func _build_snapshot() -> Dictionary:
	var instance_count: int = 0
	if world_server.instance_manager != null:
		for res: InstanceResource in world_server.instance_manager.instance_collection.values():
			instance_count += res.charged_instances.size()
	return {
		"name": str(world_info.get("name", "world")),
		"population": world_server.connected_players.size(),
		"instances": instance_count,
		"uptime_s": int(Time.get_ticks_msec() / 1000.0),
		"ts": int(Time.get_unix_time_from_system()),
	}


# --- RPC: world receives from master ---

@rpc("any_peer")
func heartbeat(_snapshot: Dictionary) -> void:
	# Server-bound payload — declared so Godot's RPC table accepts the call;
	# the master side overrides this with its own implementation.
	pass


## Master tells this world to flush all connected players + snapshot the DB.
@rpc("authority")
func master_save() -> void:
	if world_server == null or database == null:
		return
	var saved: int = database.save_all_connected(world_server.connected_players)
	var ok: bool = database.backup_database()
	Logger.info("Dashboard 'save' triggered: %d player(s), backup %s." % [saved, "ok" if ok else "FAILED"])


## Master tells this world to shut down gracefully. Final save runs first.
@rpc("authority")
func master_shutdown() -> void:
	if world_server == null or database == null:
		return
	Logger.info("Dashboard 'shutdown' triggered — saving + quitting.")
	database.save_all_connected(world_server.connected_players)
	database.backup_database()
	get_tree().quit.call_deferred()


## Master pushes a system message to every connected player in this world.
@rpc("authority")
func master_broadcast(message: String) -> void:
	if world_server == null or world_server.chat_service == null:
		return
	for peer_id: int in world_server.connected_players:
		var player: PlayerResource = world_server.connected_players[peer_id]
		if player == null:
			continue
		world_server.chat_service.push_system_to_player(null, player.player_id, "[Broadcast] " + message)
	Logger.info("Dashboard broadcast sent: %s" % message)


func _on_connection_failed() -> void:
	print("Failed to connect to the MasterServer as WorldServer.")
	await get_tree().create_timer(3.0).timeout
	start_client_to_master_server(world_info)


func _on_server_disconnected() -> void:
	print("WorldServer disconnected from MasterServer.")
	await get_tree().create_timer(3.0).timeout
	start_client_to_master_server(world_info)


@rpc("any_peer")
func fetch_server_info(_info: Dictionary) -> void:
	pass


@rpc("authority")
func fetch_token(auth_token: String, username: String, character_id: int) -> void:
	token_received.emit(auth_token, username, character_id)


@rpc("any_peer")
func player_disconnected(_username: String) -> void:
	pass


@rpc("authority")
func create_player_character_request(gateway_id: int, peer_id: int, username: String, character_data: Dictionary) -> void:
	var character_id: int = database.create_player_character(username, character_data)
	
	player_character_creation_result.rpc_id(
		1,
		gateway_id,
		peer_id,
		username,
		character_id
	)


@rpc("any_peer")
func player_character_creation_result(_gateway_id: int, _peer_id: int, _username: String, _result_code: int) -> void:
	pass


@rpc("authority")
func request_player_characters(gateway_id: int, peer_id: int, username: String) -> void:
	var characters: Dictionary = database.get_account_characters(username)
	
	receive_player_characters.rpc_id(
		1,
		characters,
		gateway_id,
		peer_id
	)


@rpc("any_peer")
func receive_player_characters(_gateway_id: int, _peer_id: int, _player_characters: Dictionary) -> void:
	pass


@rpc("authority")
func request_login(
	gateway_id: int,
	peer_id: int,
	username: String,
	character_id: int
) -> void:
	var player: PlayerResource = database.get_player_resource(character_id)
	if player == null:
		return

	if player.account_name != username:
		return
	result_login.rpc_id(
		1,
		OK,
		gateway_id,
		peer_id,
		username,
		character_id,
	)


@rpc("any_peer")
func result_login(
	_result_code: int,
	_gateway_id: int,
	_peer_id: int,
	_username: String,
	_character_id: int
) -> void:
	pass
