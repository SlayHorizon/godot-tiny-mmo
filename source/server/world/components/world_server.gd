class_name WorldServer
extends BaseMultiplayerEndpoint
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

@export var database: WorldDatabase
@export var world_manager: WorldManagerClient
@export var world_clock: WorldClock
@export var chat_service: ChatService

## The full-DB backup (WAL checkpoint TRUNCATE + whole-file copy) is the heaviest
## periodic op and its cost grows with DB size, so it runs on a MULTIPLE of the save
## interval instead of every save. Player saves still flush every 5 min (cheap per
## player, keeps the data-loss window short); the backup folds in every Nth save. Side
## benefit: with keep_last=10 the retained history stretches from ~50 min to ~5 h.
## See docs/netcode_perf_audit.md.
const BACKUP_EVERY_N_SAVES: int = 6  # 6 × 5 min = 30 min
var _periodic_save_count: int = 0

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

	# Periodic save + backup. 5 minutes balances "low data loss on crash"
	# against "no churning the disk every second." backup_database keeps the
	# last 10 snapshots, so we get ~50 minutes of recoverable history.
	var save_timer: Timer = Timer.new()
	save_timer.name = "PeriodicSaveTimer"
	save_timer.wait_time = 5.0 * 60.0
	save_timer.autostart = true
	save_timer.timeout.connect(_on_periodic_save)
	add_child(save_timer)

	# Network/tick profiler report — one aggregate [NET] line per second across the
	# whole world process (docs/netcode_perf_audit.md, F0). Cheap; toggle the output
	# with NetProfiler.enabled. This is the measurement backbone for load testing.
	var net_report_timer: Timer = Timer.new()
	net_report_timer.name = "NetProfilerTimer"
	net_report_timer.wait_time = 1.0
	net_report_timer.autostart = true
	net_report_timer.timeout.connect(
		func() -> void: NetProfiler.report_and_reset(connected_players.size(), 1.0)
	)
	add_child(net_report_timer)


func _on_periodic_save() -> void:
	# Refresh last-seen for everyone online so a crash only loses at most one
	# save interval of it (the authoritative stamp is on disconnect).
	var now_unix_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	for pid: int in connected_players:
		var p: PlayerResource = connected_players[pid]
		if p != null:
			p.lb_stats["last_seen_ms"] = now_unix_ms
	var saved: int = database.save_all_connected(connected_players)
	# The backup (checkpoint + full-file copy) only runs every Nth save — see
	# BACKUP_EVERY_N_SAVES. Shutdown / master-triggered saves back up separately.
	_periodic_save_count += 1
	if _periodic_save_count % BACKUP_EVERY_N_SAVES != 0:
		ServerLog.info("Periodic save: %d player(s) flushed." % saved)
		return
	var ok: bool = database.backup_database()
	ServerLog.info("Periodic save: %d player(s) flushed, backup %s." % [saved, "ok" if ok else "FAILED"])


## Best-effort save on a window-manager close (editor run / windowed build).
## NOTE: Godot headless does NOT deliver _notification on SIGINT/SIGTERM, so this
## does NOT fire on `systemctl stop` (verified). The reliable production save path
## is master-triggered (master_save / master_restart, RPC-driven so it's signal-
## free) — the deploy calls /v1/save_all before stopping. This handler stays only
## for the interactive/windowed case; it's harmless and never the sole safety net.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if database == null:
		return
	var saved: int = database.save_all_connected(connected_players)
	var ok: bool = database.backup_database()
	ServerLog.info("Shutdown save: %d player(s) flushed, backup %s." % [saved, "ok" if ok else "FAILED"])


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.peer_authentication_failed.connect(_on_peer_authentication_failed)
	api.set_auth_callback(_authentication_callback)


func _on_peer_connected(peer_id: int) -> void:
	ServerLog.info("Peer %d connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	ServerLog.info("Peer %d disconnected." % peer_id)
	# Sparring: if mid-match, end it before we tear down so the survivor gets
	# the win + teleport instead of being stranded in the arena.
	SparringService.on_peer_disconnected(peer_id)
	# Dungeon: sweep them from any lobby queue / live run so the group + run maps
	# don't keep a phantom member (and the private instance can free when empty).
	DungeonService.on_peer_disconnected(peer_id)
	# Drop rate-limit counters so a reconnect starts with a clean window.
	RateLimiter.forget(peer_id)

	world_manager.player_disconnected.rpc_id(1, connected_players[peer_id].account_name)
	var player: PlayerResource = connected_players.get(peer_id)
	if not player:
		return

	# Bank the elapsed session time before persisting. Stored as a flat key on
	# lb_stats so it rides existing stats_json serialization (no schema change).
	if player.session_start_ms > 0:
		@warning_ignore("integer_division")
		var session_seconds: int = (Time.get_ticks_msec() - player.session_start_ms) / 1000
		if session_seconds > 0:
			player.lb_stats["played_seconds"] = int(player.lb_stats.get("played_seconds", 0)) + session_seconds

	# Last-seen stamp (unix ms). Rides lb_stats/stats_json like played_seconds —
	# no schema change; profile.get buckets it into coarse "last seen" text.
	player.lb_stats["last_seen_ms"] = int(Time.get_unix_time_from_system() * 1000.0)

	database.save_player(player)

	player_id_to_peer_id.erase(player.player_id)
	BlockList.clear_player(player.player_id)

	player.current_peer_id = 0
	connected_players.erase(peer_id)


func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	multiplayer.send_auth(peer_id, "data_from_server".to_ascii_buffer())


func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)


func _authentication_callback(peer_id: int, data: PackedByteArray) -> void:
	# Cast as String if not returns empty String
	var auth_token: String = bytes_to_var(data) as String
	print("Peer: %d is trying to connect with data: \"%s\"." % [peer_id, auth_token])
	if is_valid_authentication_token(auth_token):
		multiplayer.complete_auth(peer_id)
		connected_players[peer_id] = token_list[auth_token]
		connected_players[peer_id].current_peer_id = peer_id
		# Stamp the session start so the played_seconds counter can advance on
		# disconnect. Reset on every fresh login.
		connected_players[peer_id].session_start_ms = Time.get_ticks_msec()
		player_id_to_peer_id[connected_players[peer_id].player_id] = peer_id
		# Hydrate the per-player block-list cache so chat filtering is a
		# dictionary lookup, not a JSON parse per message.
		BlockList.set_for(connected_players[peer_id].player_id, connected_players[peer_id].blocked_ids)
		token_list.erase(auth_token)
		data_push.rpc_id.call_deferred(peer_id, &"player_id.set", {"player_id": connected_players[peer_id].player_id})
		data_push.rpc_id.call_deferred(peer_id, &"active_guild_id.set", {"active_guild_id": connected_players[peer_id].active_guild_id})
	else:
		peer.disconnect_peer(peer_id)


func is_valid_authentication_token(auth_token: String) -> bool:
	if token_list.has(auth_token):
		return true
	return false


@export var instance_manager: InstanceManagerServer

var data_handlers: Dictionary[StringName, DataRequestHandler]


func _ready() -> void:
	# Publish the live world-server singleton. Common-side code reaches it as the
	# typed `WorldServer.curr` (the export plugin stubs this static, so naming the
	# class in common/ stays client-export-safe).
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


## Recall payoff (called via WorldServer.curr from RecallAbility.channel_complete): send
## [param player] home to the town hub. Delegates to the InstanceManager by peer,
## which resolves the current instance authoritatively and reuses the warper/jail
## travel path.
func recall_player(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	instance_manager.recall_player(int(player.player_resource.current_peer_id))


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
