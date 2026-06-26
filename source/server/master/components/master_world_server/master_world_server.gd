class_name WorldManagerServer
extends BaseMultiplayerEndpoint


@export var authentication_manager: AuthenticationManager
@export var gateway_manager: GatewayManagerServer

var connected_worlds: Dictionary[int, Dictionary]


func _ready() -> void:
	var configuration: Dictionary = ConfigFileUtils.load_section(
		"world-manager-server",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/master_config.cfg")
	)
	create(Role.SERVER, configuration.bind_address, configuration.port)


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	print("World: %d is connected to WorldManager." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var dropped: Dictionary = connected_worlds.get(peer_id, {})
	connected_worlds.erase(peer_id)
	# Push the updated roster to every gateway so their cached world list (served
	# at /v1/worlds) drops the dead world. Connect already broadcasts (see
	# fetch_server_info); without this, a stopped world would linger in selection.
	gateway_manager.update_worlds_info.rpc(get_public_worlds())
	print("World: %d is disconnected from WorldManager." % peer_id)
	var world_name: String = str(dropped.get("info", {}).get("name", "world#%d" % peer_id))
	DiscordNotifier.notify_world_disconnected(world_name)


@rpc("any_peer")
func fetch_server_info(info: Dictionary) -> void:
	var game_server_id: int = multiplayer_api.get_remote_sender_id()
	connected_worlds[game_server_id] = info
	# Stamp connect time so the dashboard can show "connected for X minutes".
	connected_worlds[game_server_id]["connected_at"] = int(Time.get_unix_time_from_system())
	gateway_manager.update_worlds_info.rpc(get_public_worlds())
	var world_name: String = str(info.get("info", {}).get("name", "world#%d" % game_server_id))
	DiscordNotifier.notify_world_connected(world_name)


## Client-safe view of the live worlds: name / motd / pvp only. The full roster
## (connected_worlds) also holds each world's address, port and heartbeat snapshot
## (player rosters, chat tail, server logs) — that must never reach a game client,
## so every world-list payload (login/list responses + gateway broadcasts) is
## projected through here. The raw roster stays server-side for handoff/dashboard.
func get_public_worlds() -> Dictionary:
	var out: Dictionary = {}
	for world_id: int in connected_worlds:
		var info: Dictionary = connected_worlds[world_id].get("info", {})
		out[world_id] = {
			"info": {
				"name": info.get("name", ""),
				"motd": info.get("motd", ""),
				"pvp": info.get("pvp", false),
			}
		}
	return out


## Resolve a world's display name to its live peer id, or 0 if no world by that
## name is currently connected. Character ids are per-world (each world has its
## own DB), so a last-login kick must target the player's actual world by name —
## broadcasting the id could boot a same-id character on a different world.
func world_id_by_name(world_name: String) -> int:
	if world_name.is_empty():
		return 0
	for world_id: int in connected_worlds:
		if connected_worlds[world_id].get("info", {}).get("name", "") == world_name:
			return world_id
	return 0


## Periodic snapshot push from each world. Replaces the live numbers on the
## fetched info so the dashboard always reflects what the world is reporting.
@rpc("any_peer")
func heartbeat(snapshot: Dictionary) -> void:
	var world_peer_id: int = multiplayer_api.get_remote_sender_id()
	if not connected_worlds.has(world_peer_id):
		return
	connected_worlds[world_peer_id]["heartbeat"] = snapshot
	connected_worlds[world_peer_id]["last_heartbeat_at"] = int(Time.get_unix_time_from_system())


# --- Dashboard-driven outbound RPCs (master → world) ---

## Tell the world with this peer_id to flush all players to DB + backup.
func tell_world_to_save(world_peer_id: int) -> bool:
	if not connected_worlds.has(world_peer_id):
		return false
	master_save.rpc_id(world_peer_id)
	return true


## Tell the world to shut down gracefully (save then quit).
func tell_world_to_shutdown(world_peer_id: int) -> bool:
	if not connected_worlds.has(world_peer_id):
		return false
	master_shutdown.rpc_id(world_peer_id)
	return true


## Push a system message to every connected player on this world.
func tell_world_to_broadcast(world_peer_id: int, message: String) -> bool:
	if not connected_worlds.has(world_peer_id):
		return false
	master_broadcast.rpc_id(world_peer_id, message)
	return true


## Tell one world to run a staged restart countdown (warns players over [param seconds],
## then a final save). Does NOT quit the world — the deploy's `systemctl stop` does that
## (and saves again via WorldServer._notification). Returns true if the world is known.
func tell_world_to_restart(world_peer_id: int, seconds: int, message: String) -> bool:
	if not connected_worlds.has(world_peer_id):
		return false
	master_restart.rpc_id(world_peer_id, seconds, message)
	return true


## Fan the restart countdown out to EVERY connected world in one shot (the deploy
## makes a single call; the master knows the whole roster). Returns the count notified.
func tell_all_worlds_to_restart(seconds: int, message: String) -> int:
	var count: int = 0
	for world_peer_id: int in connected_worlds:
		master_restart.rpc_id(world_peer_id, seconds, message)
		count += 1
	return count


# Stubs declared so Godot's RPC table accepts the outbound calls. World side
# implements the actual behavior in WorldManagerClient.
@rpc("authority") func master_save() -> void: pass
@rpc("authority") func master_shutdown() -> void: pass
@rpc("authority") func master_broadcast(_message: String) -> void: pass
@rpc("authority") func master_restart(_seconds: int, _message: String) -> void: pass
@rpc("authority") func master_mute(_player_id: int, _reason: String, _duration_ms: int) -> void: pass
@rpc("authority") func master_unmute(_player_id: int) -> void: pass
@rpc("authority") func master_jail(_player_id: int, _reason: String, _duration_ms: int) -> void: pass
@rpc("authority") func master_unjail(_player_id: int) -> void: pass
@rpc("authority") func master_kick(_player_id: int) -> void: pass
@rpc("authority") func master_grant_role(_player_id: int, _role: String) -> void: pass
@rpc("authority") func master_revoke_role(_player_id: int, _role: String) -> void: pass


## Dashboard helpers — each returns true if the targeted world is known.
func tell_world_to_mute(world_id: int, player_id: int, reason: String, duration_ms: int) -> bool:
	if not connected_worlds.has(world_id): return false
	master_mute.rpc_id(world_id, player_id, reason, duration_ms)
	return true


func tell_world_to_unmute(world_id: int, player_id: int) -> bool:
	if not connected_worlds.has(world_id): return false
	master_unmute.rpc_id(world_id, player_id)
	return true


func tell_world_to_jail(world_id: int, player_id: int, reason: String, duration_ms: int) -> bool:
	if not connected_worlds.has(world_id): return false
	master_jail.rpc_id(world_id, player_id, reason, duration_ms)
	return true


func tell_world_to_unjail(world_id: int, player_id: int) -> bool:
	if not connected_worlds.has(world_id): return false
	master_unjail.rpc_id(world_id, player_id)
	return true


func tell_world_to_kick(world_id: int, player_id: int) -> bool:
	if not connected_worlds.has(world_id): return false
	master_kick.rpc_id(world_id, player_id)
	return true


func tell_world_to_grant_role(world_id: int, player_id: int, role: String) -> bool:
	if not connected_worlds.has(world_id): return false
	master_grant_role.rpc_id(world_id, player_id, role)
	return true


func tell_world_to_revoke_role(world_id: int, player_id: int, role: String) -> bool:
	if not connected_worlds.has(world_id): return false
	master_revoke_role.rpc_id(world_id, player_id, role)
	return true


@rpc("authority")
func fetch_token(_auth_token: String, _username: String, _character_id: int) -> void:
	pass


@rpc("any_peer")
func player_disconnected(username: String) -> void:
	var account: AccountResource = authentication_manager.account_collection.collection.get(username)
	if account != null:
		account.peer_id = 0 # frees the account for a fresh login (see login_request)
		authentication_manager.active_accounts.erase(account.username)


@rpc("authority")
func create_player_character_request(_gateway_id: int, _peer_id: int, _username: String, _character_data: Dictionary) -> void:
	pass


@rpc("any_peer")
func player_character_creation_result(gateway_id: int, peer_id: int, username: String, result_code: int) -> void:
	var world_id: int = multiplayer_api.get_remote_sender_id()
	if result_code:
		var account: AccountResource = authentication_manager.account_collection.collection.get(username)
		if not account:
			return
		account.last_world_name = connected_worlds[world_id].get("info", {}).get("name", "")
		account.last_character_id = result_code
		account.peer_id = peer_id # mark connected so a second login is refused
		if OS.has_feature("debug"):
			authentication_manager.save_account_collection()
		var auth_token: String = authentication_manager.generate_random_token()
		fetch_token.rpc_id(world_id, auth_token, username, result_code)
		
		gateway_manager.gateway_response.rpc_id(
			gateway_id,
			peer_id,
			{
				"auth-token": auth_token,
				"address": connected_worlds[world_id]["address"],
				"port": connected_worlds[world_id]["port"]
			}
		)
	else:
		gateway_manager.player_character_creation_result.rpc_id(
			gateway_id, peer_id, result_code
		)


@rpc("any_peer")
func request_player_characters(_gateway_id: int, _peer_id: int, _username: String) -> void:
	pass


@rpc("any_peer")
func request_login(_gateway_id: int, _peer_id: int, _username: String, _character_id: int) -> void:
	pass


@rpc("any_peer")
func result_login(result_code: int, gateway_id: int, peer_id: int, username: String, character_id: int) -> void:
	var world_id: int = multiplayer_api.get_remote_sender_id()
	if result_code == OK:
		# Mark the account connected so login_request refuses a second login;
		# player_disconnected clears it on world disconnect.
		var account: AccountResource = authentication_manager.account_collection.collection.get(username)
		if account != null:
			account.peer_id = peer_id
		var auth_token: String = authentication_manager.generate_random_token()
		fetch_token.rpc_id(world_id, auth_token, username, character_id)
		await get_tree().create_timer(0.5).timeout
		gateway_manager.gateway_response.rpc_id(
			gateway_id,
			peer_id,
			{
				"auth-token": auth_token,
				"address": connected_worlds[world_id]["address"],
				"port": connected_worlds[world_id]["port"]
			}
		)


@rpc("any_peer")
func receive_player_characters(player_characters: Dictionary, gateway_id: int, peer_id: int) -> void:
	gateway_manager.gateway_response.rpc_id(
		gateway_id,
		peer_id,
		player_characters
	)
