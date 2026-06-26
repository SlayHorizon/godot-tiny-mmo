extends BaseMultiplayerEndpoint


signal connection_changed(connected_to_server: bool)
signal authentication_requested

var peer_id: int
var is_connected_to_server: bool = false:
	set(value):
		is_connected_to_server = value
		connection_changed.emit(value)

var authentication_token: String

## Crossfade duration when area music changes on entering a new instance/map.
const MUSIC_CROSSFADE_S: float = 1.5
## Boss-event tracks (client assets): a looping combat track + a one-shot victory sting.
const MUSIC_BOSS_FIGHT: String = "res://assets/audio/music/middle_boss.ogg"
const MUSIC_BOSS_VICTORY: String = "res://assets/audio/music/boss_clear.ogg"

@onready var world_clock: WorldClock = $WorldClock
@onready var audio_manager: AudioManager = $AudioManager
@onready var instance_manager: InstanceManagerClient = $InstanceManager

## The current area track, kept so a boss fight / victory sting can return to it.
var _area_music: AudioStream
## Bumped on any music-context change; cancels a pending victory-sting auto-resume so a
## map change or a new fight during the sting isn't clobbered when it finishes.
var _music_gen: int = 0
## Screen-space ambient weather overlay (leaves/rain/snow), created on first connect and
## driven by Map.weather on each area change. Client-only.
var _weather_layer: WeatherLayer


func _enter_tree() -> void:
	if not GameMode.is_client():
		queue_free()


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
	print("connecting to: ", _address, "  (port: ", _port, " ignored if URL)  token=", _authentication_token)
	print(_address, _port, _authentication_token)
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

	# Area music: crossfade to each map's track as the player enters it. Connect once
	# (idempotent across reconnects). Replaces the old stop_music placeholder — the area
	# track now takes over from the gateway music instead of fading to silence.
	if not instance_manager.instance_changed.is_connected(_on_instance_changed):
		instance_manager.instance_changed.connect(_on_instance_changed)
	# Boss-event music cues (world boss, dungeon boss): fight / victory / end.
	# subscribe() dedupes, so re-running it on each reconnect is safe.
	subscribe(&"boss.music", _on_boss_music)
	# Ambient weather overlay — created once, driven by Map.weather on each area change.
	if _weather_layer == null:
		_weather_layer = WeatherLayer.new()
		add_child(_weather_layer)

	if OS.has_feature("debug"):
		DisplayServer.window_set_title("Client - %d" % peer_id)


## Crossfade to the new instance's map music. Maps without a `music` set keep whatever
## is already playing, so the world never snaps to silence (a small building inherits
## the overworld track, etc.). See InstanceManagerClient.instance_changed.
func _on_instance_changed(instance: InstanceClient) -> void:
	_music_gen += 1 # entering a new area cancels any pending victory-sting resume
	if instance == null or instance.instance_map == null:
		return
	var track: AudioStream = instance.instance_map.music
	if track != null:
		_area_music = track
		audio_manager.play_music_stream(track, 0.0, 0.0, MUSIC_CROSSFADE_S)
	if _weather_layer != null:
		_weather_layer.apply(instance.instance_map.weather)


## Boss-event music cue (server-driven). "fight" overrides the area track with combat
## music; "victory" plays the one-shot clear sting then returns to the area track;
## "end" (admin abort / wipe) returns to the area track with no sting.
func _on_boss_music(payload: Dictionary) -> void:
	match String(payload.get("state", "")):
		"fight":
			_music_gen += 1
			audio_manager.play_music(MUSIC_BOSS_FIGHT, 0.0, 0.0, MUSIC_CROSSFADE_S)
		"victory":
			_play_victory_sting()
		"end":
			_music_gen += 1
			_resume_area_music()


## Crossfade back to the current area track after a boss fight ends.
func _resume_area_music() -> void:
	if _area_music != null:
		audio_manager.play_music_stream(_area_music, 0.0, 0.0, MUSIC_CROSSFADE_S)


## Play the one-shot boss-clear sting, then auto-resume the area track when it ends.
## Guarded by _music_gen so a map change or a new fight during the sting cancels the
## resume rather than overriding the newer music.
func _play_victory_sting() -> void:
	_music_gen += 1
	var gen: int = _music_gen
	var sting: AudioStream = load(MUSIC_BOSS_VICTORY) as AudioStream
	if sting == null:
		_resume_area_music()
		return
	audio_manager.play_music_stream(sting, 0.0, 0.0, 0.5)
	await get_tree().create_timer(sting.get_length()).timeout
	if gen == _music_gen:
		_resume_area_music()


func _on_connection_failed() -> void:
	print("Failed to connect to the world server.")
	close_connection()


func _on_server_disconnected() -> void:
	print("Server disconnected.")
	close_connection()
	# Freeze the world so nothing acts on a dead connection, then surface a clear
	# overlay (Reconnect / Back to login) instead of the old silent freeze. Transition
	# runs PROCESS_MODE_ALWAYS, so its buttons stay live while the tree is paused.
	get_tree().paused = true
	if is_instance_valid(Transition):
		Transition.show_disconnected()


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
