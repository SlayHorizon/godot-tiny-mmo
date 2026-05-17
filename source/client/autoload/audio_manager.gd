class_name AudioManager
extends Node


@export var music_player: AudioStreamPlayer
@export var ui_player: AudioStreamPlayer
@export var max_sfx_pool_size: int = 16
@export var max_sfx_distance: float = 500.0

@export_range(0.0, 1.0, 0.001) var music_volume: float = 1.0:
	set(value):
		var bus_index: int = AudioServer.get_bus_index(&"Music")
		AudioServer.set_bus_volume_linear(bus_index, value)

@export_range(0.0, 1.0, 0.001) var sound_volume: float = 1.0:
	set(value):
		var bus_index: int = AudioServer.get_bus_index(&"Sound")
		AudioServer.set_bus_volume_linear(bus_index, value)


var _tweens: Dictionary[AudioStreamPlayer, Tween]
var _sound_cache: Dictionary[StringName, AudioStream]

var _avaible_sfx_players: Array[AudioStreamPlayer2D]
var _busy_sfx_players: Array[AudioStreamPlayer2D]


func _ready() -> void:
	if not OS.has_feature("client"):
		queue_free()
		return
	assert(is_instance_valid(music_player), "No valid music player.")
	assert(is_instance_valid(ui_player), "No valid ui player.")

	ui_player.play()
	ClientState.settings.setting_changed.connect(_on_setting_changed)
	_apply_default_settings()


func _on_setting_changed(section: StringName, property: StringName, value: Variant) -> void:
	match property:
		&"music_volume": music_volume = clampf(value, 0.0, 1.0)
		&"sound_volume": sound_volume = clampf(value, 0.0, 1.0)


func play_music(music_name: StringName, volume: float = 0.0, at_position: float = 0.0, fade_duration: float = 1.0) -> bool:
	await stop_music(fade_duration)

	var music: AudioStream = _get_sound_from_slug(music_name, &"musics")
	if not music: return false
	if music_player.stream == music: return true

	music_player.stream = music
	music_player.volume_db = -80
	music_player.play(at_position)

	fade_volume(music_player, volume, clampf(fade_duration, 0.0, 10.0))
	return true


func stop_music(fade_out_duration: float = 1.0) -> void:
	if music_player.playing:
		fade_volume(music_player, -80, clampf(fade_out_duration, 0.0, 10.0))
		await _tweens[music_player].finished


func play_ui_sound(sound_name: StringName, pitch: float = 1.0) -> bool:
	var sound: AudioStream = _get_sound_from_slug(sound_name, &"sfxs")
	if not sound: return false

	var playback: AudioStreamPlaybackPolyphonic = ui_player.get_stream_playback()
	playback.play_stream(sound, 0, 0, pitch)

	return true


func play_sfx(sound_name: StringName, position: Vector2 = Vector2.ZERO, pitch: float = 1.0) -> bool:
	var sound: AudioStream = _get_sound_from_slug(sound_name, &"sfxs")
	if not sound: return false

	var player: AudioStreamPlayer2D = get_available_sfx_player()
	if not player: return false

	player.stream = sound
	player.global_position = position
	player.pitch_scale = pitch

	_acquire_sfx_player(player)
	player.play()

	return true


func get_available_sfx_player() -> AudioStreamPlayer2D:
	if _avaible_sfx_players.is_empty():
		_allocate_players()
	return _avaible_sfx_players.pop_back()


func fade_volume(player: AudioStreamPlayer, to_volume: float, duration: float = 1.0) -> void:
	_remove_tween(player)

	var tween = create_tween()
	var is_fading_out: bool = player.volume_db > to_volume
	tween.tween_property(
		player, 
		"volume_db",
		to_volume,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN if is_fading_out else Tween.EASE_OUT)

	tween.finished.connect(_on_fade_finished.bind(player, is_fading_out), CONNECT_ONE_SHOT)
	_tweens[player] = tween


func _acquire_sfx_player(sfx_player: AudioStreamPlayer2D) -> void:
	_avaible_sfx_players.erase(sfx_player)
	if not _busy_sfx_players.has(sfx_player):
		_busy_sfx_players.append(sfx_player)


func _release_sfx_player(sfx_player: AudioStreamPlayer2D) -> void:
	_busy_sfx_players.erase(sfx_player)

	if _avaible_sfx_players.size() > max_sfx_pool_size:
		sfx_player.queue_free()
		return
	
	if not _avaible_sfx_players.has(sfx_player):
		_avaible_sfx_players.append(sfx_player)


func _allocate_players() -> void:
	for player: AudioStreamPlayer2D in _busy_sfx_players:
		if not player.playing:
			_release_sfx_player(player)
			return
	
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.bus = &"Sound"
	player.max_distance = max_sfx_distance
	add_child(player, true)
	_avaible_sfx_players.append(player)
	player.finished.connect(_release_sfx_player.bind(player))


func _remove_tween(player: AudioStreamPlayer) -> void:
	if not _tweens.has(player): return
	var tween: Tween = _tweens.get(player)
	tween.kill()
	_tweens.erase(player)


func _on_fade_finished(player: AudioStreamPlayer, was_fading_out) -> void:
	_remove_tween(player)
	if was_fading_out:
		player.stop()


## from_content = &"sfxs", &"musics"
func _get_sound_from_slug(sound_name: StringName, from_content: StringName = &"musics") -> AudioStream:
	if _sound_cache.has(sound_name):
		return _sound_cache.get(sound_name)
	
	if not ContentRegistryHub.registry_of(from_content): return null
	var audio: Resource = ContentRegistryHub.load_by_slug(from_content, sound_name)
	if (not audio) or (not audio is AudioStream): return null
	
	_sound_cache[sound_name] = audio
	return audio


func _apply_default_settings() -> void:
	var settings: Dictionary = ClientState.settings.data
	for property in settings[&"general"]:
		var value: Variant = settings[&"general"][property]
		_on_setting_changed(&"general", property, value)