class_name SfxPool
extends Node
## Pool-based spatial audio playback system.

## Max amount of [AudioStreamPlayer2D] that can be loaded on runtime.
@export_range(1, 32, 1) var max_players_size: int = 16
## Default max distance for [AudioStreamPlayer2D].
@export var max_distance: float = 500.0
## Default audio bus
@export var audio_bus: StringName = &"Sound"

var available_players: Array[AudioStreamPlayer2D]
var busy_players: Array[AudioStreamPlayer2D]


## Play a spatial sound using the given [AudioStream].[br]
## [position] - The 2D world position that the sound will play from.[br]
## [override_max_distance] - Overrides the default max distance. leave at 0.0 to use default distance.
func play_stream(sound: AudioStream, position: Vector2, override_max_distance: float = 0.0, pitch: float = 1.0) -> bool:
	if not sound: return false

	var max_range: float = override_max_distance if override_max_distance > 0.0 else max_distance
	if not _can_play_at_position(position, max_range): return false

	var player: AudioStreamPlayer2D = get_available_player()
	if not player: return false

	player.stream = sound
	player.pitch_scale = pitch
	player.global_position = position
	player.max_distance = max_range

	mark_player_busy(player)
	player.play()
	return true


## Gets an available [AudioStreamPlayer2D]. If no player is available, attempts to instantiate one.
func get_available_player() -> AudioStreamPlayer2D:
	if not available_players.is_empty():
		return available_players.pop_back()

	var total_players: int = busy_players.size() + available_players.size()
	if total_players >= max_players_size: return null
	
	return _create_player()


## Marks the player as currently in use.
func mark_player_busy(player: AudioStreamPlayer2D) -> void:
	available_players.erase(player)
	if busy_players.has(player): return
	busy_players.push_back(player)


## Resets and returns the player to the available pool.
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


func _can_play_at_position(position: Vector2, max_range: float) -> bool:
	var local_player: LocalPlayer = ClientState.local_player
	if not is_instance_valid(local_player): return true

	return local_player.global_position.distance_to(position) <= max_range