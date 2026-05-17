class_name AudioManager
extends Node


@export var music_player: AudioStreamPlayer
@export var ui_player: AudioStreamPlayer
@export var sfx_player: SfxPool

@export_range(0.0, 1.0, 0.001) var music_volume: float = 1.0:
	set(value): set_music_volume(value)

@export_range(0.0, 1.0, 0.001) var sound_volume: float = 1.0:
	set(value): set_sfx_volume(value)

var _tweens: Dictionary[AudioStreamPlayer, Tween]
var _sound_cache: Dictionary[StringName, AudioStream]
var _pending_music: PendingMusic


func _ready() -> void:
	if not OS.has_feature("client"):
		queue_free()
		return
	assert(is_instance_valid(music_player), "No valid music player.")
	assert(is_instance_valid(ui_player), "No valid ui player.")
	assert(is_instance_valid(sfx_player), "No valid sfx player.")

	ui_player.play()
	ClientState.settings.setting_changed.connect(_on_setting_changed)
	_apply_default_settings()


func _on_setting_changed(section: StringName, property: StringName, value: Variant) -> void:
	match property:
		&"music_volume": music_volume = clampf(value, 0.0, 1.0)
		&"sound_volume": sound_volume = clampf(value, 0.0, 1.0)

#region Music

func set_music_volume(volume_linear: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(&"Music")
	AudioServer.set_bus_volume_linear(bus_index, clampf(volume_linear, 0.0, 1.0))


func play_music(music_name: StringName, volume: float = 0.0, at_position: float = 0.0, fade_duration: float = 1.0) -> bool:
	return play_music_stream(_get_sound_from_slug(music_name, &"musics"), volume, at_position, fade_duration)


func play_music_stream(music: AudioStream, volume: float = 0.0, at_position: float = 0.0, fade_duration: float = 1.0) -> bool:
	if not music: return false
	if music_player.playing and music_player.stream == music: return true

	_pending_music = PendingMusic.new()
	_pending_music.stream = music
	_pending_music.volume = volume
	_pending_music.at_position = at_position
	_pending_music.fade_duration = fade_duration

	if music_player.playing:
		stop_music(fade_duration)
	else:
		_start_music()

	return true


func stop_music(fade_out_duration: float = 1.0) -> void:
	if music_player.playing:
		fade_volume(music_player, -80, clampf(fade_out_duration, 0.0, 10.0))

#endregion

#region UI Sound

func play_ui_sound(sound_name: StringName, pitch: float = 1.0) -> bool:
	return play_ui_sound_stream(_get_sound_from_slug(sound_name, &"sfxs"))


func play_ui_sound_stream(sound: AudioStream, pitch: float = 1.0) -> bool:
	if not sound: return false
	var playback: AudioStreamPlaybackPolyphonic = ui_player.get_stream_playback()
	playback.play_stream(sound, 0, 0, pitch)
	return true

#endregion

#region Sound Effect

func set_sfx_volume(volume_linear: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(&"Sound")
	AudioServer.set_bus_volume_linear(bus_index, clampf(volume_linear, 0.0, 1.0))


func play_sfx(sound_name: StringName, position: Vector2, override_max_distance: int = 0, pitch: float = 1.0) -> bool:
	var sound: AudioStream = _get_sound_from_slug(sound_name, &"sfxs")
	return sfx_player.play_stream(sound, position, override_max_distance, pitch)


func play_sfx_stream(sound: AudioStream, position: Vector2, override_max_distance: int = 0, pitch: float = 1.0) -> bool:
	return sfx_player.play_stream(sound, position, override_max_distance, pitch)

#endregion


#region Helpers

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


func _start_music() -> void:
	if not _pending_music: return

	music_player.stream = _pending_music.stream
	music_player.volume_db = -80
	music_player.play(_pending_music.at_position)
	fade_volume(music_player, _pending_music.volume, _pending_music.fade_duration)
	_pending_music = null


func _remove_tween(player: AudioStreamPlayer) -> void:
	if not _tweens.has(player): return
	var tween: Tween = _tweens.get(player)
	tween.kill()
	_tweens.erase(player)


func _on_fade_finished(player: AudioStreamPlayer, was_fading_out: bool) -> void:
	_remove_tween(player)
	if was_fading_out:
		player.stop()

	if _pending_music:
		_start_music()


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

#endregion

class PendingMusic:
	var stream: AudioStream
	var volume: float
	var at_position: float
	var fade_duration: float