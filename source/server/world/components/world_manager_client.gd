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
	print("Successfully connected to the MasterServer as WorldServer - Peer ID:%d!" % multiplayer.get_unique_id())
	# Address reported to clients. Two forms supported:
	#   • bare host like "127.0.0.1" — paired with `port` to build ws://host:port
	#   • full URL like "wss://ws.example.com/world/1" — used as-is, port ignored
	# The latter is the production path when Caddy/nginx proxies WSS by path.
	# Set `public_url` in [world-server] of world.cfg to override the localhost
	# default; leave unset for local-dev where address+port is enough.
	var reported_address: String = str(world_info.get("public_url", "127.0.0.1"))
	fetch_server_info.rpc_id(
		1,
		{
			"port": world_info.port,
			"address": reported_address,
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

	# Lightweight player roster — fields the dashboard needs to render the
	# Players table + drive per-player actions.
	var players: Array = []
	for peer_id: int in world_server.connected_players:
		var p: PlayerResource = world_server.connected_players[peer_id]
		if p == null:
			continue
		players.append({
			"peer_id":      peer_id,
			"player_id":    p.player_id,
			"name":         p.display_name,
			"account":      p.account_name,
			"instance":     p.current_instance,
			"level":        p.level,
			"roles":        p.server_roles.keys(),
			# Surface punishment state so the dashboard can render "Unmute"/
			# "Unjail" instead of duplicating buttons that no-op or fail.
			"is_muted":     MuteList.is_muted(p.account_name),
			"is_jailed":    JailList.is_jailed(p.account_name),
		})

	# Recent channel chat (excludes DMs) and the in-memory log tail. Both are
	# size-capped on the producer side, so the heartbeat stays small even on
	# a busy server.
	var recent_chat: Array = []
	if world_server.chat_service != null:
		recent_chat = world_server.chat_service.recent(20)

	return {
		"name": str(world_info.get("name", "world")),
		"population": world_server.connected_players.size(),
		"instances": instance_count,
		"uptime_s": int(Time.get_ticks_msec() / 1000.0),
		"ts": int(Time.get_unix_time_from_system()),
		"players": players,
		"recent_chat": recent_chat,
		"recent_log": Array(ServerLog.recent(40)),
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
	ServerLog.info("Dashboard 'save' triggered: %d player(s), backup %s." % [saved, "ok" if ok else "FAILED"])


## Master tells this world to shut down gracefully. Final save runs first.
@rpc("authority")
func master_shutdown() -> void:
	if world_server == null or database == null:
		return
	ServerLog.info("Dashboard 'shutdown' triggered — saving + quitting.")
	database.save_all_connected(world_server.connected_players)
	database.backup_database()
	get_tree().quit.call_deferred()


## Master tells this world to run a staged restart countdown: warn every connected
## player at decreasing marks (5m / 2m / 1m / 30s / 10s, only those <= total), then a
## final save when it elapses. It does NOT quit — the deploy's `systemctl stop` stops
## the process (and saves again via WorldServer._notification). The deploy waits the
## same [param seconds] before stopping, so the countdown and the stop line up.
@rpc("authority")
func master_restart(seconds: int, message: String) -> void:
	if world_server == null or world_server.chat_service == null:
		return
	var note: String = message if not message.is_empty() else "Server restarting for an update."
	ServerLog.info("Restart countdown started: %ds — %s" % [seconds, note])
	var remaining: int = maxi(seconds, 0)
	_broadcast_restart_notice(remaining, note)  # immediate heads-up
	for mark: int in [300, 120, 60, 30, 10]:
		if mark >= remaining:
			continue
		await get_tree().create_timer(remaining - mark).timeout
		remaining = mark
		_broadcast_restart_notice(remaining, note)
	if remaining > 0:
		await get_tree().create_timer(remaining).timeout
	# Insurance save in case the deploy's stop is delayed or never lands.
	if database != null:
		var saved: int = database.save_all_connected(world_server.connected_players)
		database.backup_database()
		ServerLog.info("Restart countdown elapsed — final save (%d player(s)); awaiting stop." % saved)


## One restart-warning line to every connected player, phrased in minutes or seconds.
func _broadcast_restart_notice(remaining: int, note: String) -> void:
	var when: String
	if remaining >= 60:
		var mins: int = int(round(remaining / 60.0))
		when = "%d minute%s" % [mins, "" if mins == 1 else "s"]
	else:
		when = "%d second%s" % [remaining, "" if remaining == 1 else "s"]
	var text: String = "[Server] Restart in %s. %s" % [when, note]
	for peer_id: int in world_server.connected_players:
		var player: PlayerResource = world_server.connected_players[peer_id]
		if player == null:
			continue
		world_server.chat_service.push_system_to_player(null, player.player_id, text)


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
	ServerLog.info("Dashboard broadcast sent: %s" % message)


# --- Per-player moderation actions (master → world) ---
#
# All target a specific player_id. The world looks up the matching online
# PlayerResource (or no-ops if the player went offline between dashboard
# click and RPC arrival) and delegates to the existing service so behavior
# matches the equivalent chat command.

@rpc("authority")
func master_mute(player_id: int, reason: String, duration_ms: int) -> void:
	var account: String = _account_for_id(player_id)
	if account.is_empty():
		ServerLog.warn("Dashboard mute: no account for player #%d" % player_id)
		return
	MuteList.mute(account, reason, 0, duration_ms)
	ServerLog.info("Dashboard mute: @%s (#%d, reason=%s, dur=%dms)" % [account, player_id, reason, duration_ms])
	_notify_player(player_id, "You have been muted by a moderator.%s" % (
		"\nReason: " + reason if not reason.is_empty() else ""
	))


@rpc("authority")
func master_unmute(player_id: int) -> void:
	var account: String = _account_for_id(player_id)
	if not account.is_empty() and MuteList.unmute(account):
		ServerLog.info("Dashboard unmute: @%s (#%d)" % [account, player_id])
		_notify_player(player_id, "You have been unmuted.")


@rpc("authority")
func master_jail(player_id: int, reason: String, duration_ms: int) -> void:
	var account: String = _account_for_id(player_id)
	if account.is_empty():
		ServerLog.warn("Dashboard jail: no account for player #%d" % player_id)
		return
	JailList.jail(account, reason, 0, duration_ms)
	# If they're online, send them to jail right now via the existing helper.
	var peer_id: int = world_server.player_id_to_peer_id.get(player_id, 0)
	if peer_id != 0:
		world_server.instance_manager.send_player_to_jail(peer_id)
	ServerLog.info("Dashboard jail: @%s (#%d, reason=%s, dur=%dms)" % [account, player_id, reason, duration_ms])
	_notify_player(player_id, "You have been jailed by an admin.%s" % (
		"\nReason: " + reason if not reason.is_empty() else ""
	))


@rpc("authority")
func master_unjail(player_id: int) -> void:
	var account: String = _account_for_id(player_id)
	if not account.is_empty() and JailList.release(account):
		ServerLog.info("Dashboard unjail: @%s (#%d)" % [account, player_id])
		_notify_player(player_id, "You have been released from jail.")


## Map a character id to its account handle for account-level mute/jail: prefer
## the live resource (online), fall back to the DB (offline). "" if unknown.
func _account_for_id(player_id: int) -> String:
	var peer_id: int = world_server.player_id_to_peer_id.get(player_id, 0)
	if peer_id != 0:
		var p: PlayerResource = world_server.connected_players.get(peer_id)
		if p != null:
			return p.account_name
	if database != null and database.store != null:
		return database.store.get_player_account_name(player_id)
	return ""


@rpc("authority")
func master_kick(player_id: int) -> void:
	var peer_id: int = world_server.player_id_to_peer_id.get(player_id, 0)
	if peer_id == 0:
		return
	ServerLog.info("Dashboard kick: player #%d (peer %d)" % [player_id, peer_id])
	# Critical: there are TWO multiplayer instances on the world process —
	#   * `multiplayer` here = the master connection (this script is a client
	#     of the master server). The peer_id 1042 from the game-client
	#     connection doesn't exist in this peer table.
	#   * world_server.multiplayer_api = the world's player connections,
	#     which is where peer_id lives.
	# Using the wrong one throws "!peers_map.has(p_peer_id)" — exactly the
	# error you hit. The right peer table is the game world's.
	var game_mp: MultiplayerAPI = world_server.multiplayer_api
	if game_mp != null and game_mp.multiplayer_peer != null:
		game_mp.multiplayer_peer.disconnect_peer(peer_id)


@rpc("authority")
func master_grant_role(player_id: int, role: String) -> void:
	var peer_id: int = world_server.player_id_to_peer_id.get(player_id, 0)
	if peer_id == 0:
		return
	var target: PlayerResource = world_server.connected_players.get(peer_id)
	if target == null:
		return
	target.server_roles[role] = {}
	database.save_player(target)
	ServerLog.info("Dashboard grant: player #%d ← role '%s'" % [player_id, role])
	_notify_player(player_id, "You have been granted the role '%s'." % role)


@rpc("authority")
func master_revoke_role(player_id: int, role: String) -> void:
	var peer_id: int = world_server.player_id_to_peer_id.get(player_id, 0)
	if peer_id == 0:
		return
	var target: PlayerResource = world_server.connected_players.get(peer_id)
	if target == null or not target.server_roles.has(role):
		return
	target.server_roles.erase(role)
	database.save_player(target)
	ServerLog.info("Dashboard revoke: player #%d ← role '%s'" % [player_id, role])
	_notify_player(player_id, "Your role '%s' has been revoked." % role)


## Push a system-channel message to the given player_id if they're online.
func _notify_player(player_id: int, message: String) -> void:
	if world_server == null or world_server.chat_service == null:
		return
	world_server.chat_service.push_system_to_player(null, player_id, message)


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
