class_name SfxPool
extends Node


@export_range(0, 32, 1) var max_players_size: int = 16
@export var max_distance: float = 500.0
@export var audio_bus: StringName = &"Sound"

var available_players: Array[AudioStreamPlayer2D]
var busy_players: Array[AudioStreamPlayer2D]


func play_stream(sound: AudioStream, position: Vector2, override_max_distance: float = -1.0, pitch: float = 1.0) -> bool:
	if not sound: return false

	var player: AudioStreamPlayer2D = get_available_player()
	if not player: return false

	player.stream = sound
	player.pitch_scale = pitch
	player.global_position = position

	if override_max_distance > 0.0:
		player.max_distance = override_max_distance

	mark_player_busy(player)
	player.play()
	return true


func get_available_player() -> AudioStreamPlayer2D:
	if not available_players.is_empty():
		return available_players.pop_back()

	var total_players: int = busy_players.size() + available_players.size()
	if total_players >= max_players_size: return null
	
	return _create_player()


func mark_player_busy(player: AudioStreamPlayer2D) -> void:
	available_players.erase(player)
	if busy_players.has(player): return
	busy_players.push_back(player)


func mark_player_ready(player: AudioStreamPlayer2D) -> void:
	busy_players.erase(player)
	
	player.stream = null
	player.pitch_scale = 1.0
	player.max_distance = max_distance

	if available_players.has(player): return
	available_players.push_back(player)


func _create_player() -> AudioStreamPlayer2D:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()

	player.bus = audio_bus
	player.max_distance = max_distance

	player.finished.connect(mark_player_ready.bind(player))
	add_child(player, true)
	return player