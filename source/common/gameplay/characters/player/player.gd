class_name Player
extends Character


signal display_name_changed(new_name: String)

var player_resource: PlayerResource

var display_name: String = "Unknown":
	set = _set_display_name

var zone_flags: int = 0

var teleport_lock_until_ms: int = 0


func _init() -> void:
	pass


## Seconds the player stays down before a no-penalty respawn at the map spawn point.
const RESPAWN_DELAY: float = 3.0


## On death: tell the client (death screen + countdown + where to respawn), wait, then
## restore full health and clear the dead flag. Position is client-authoritative, so the
## client teleports itself to the spawn (see LocalPlayer); the server only owns HP/state.
## Staying dead during the delay also makes nearby enemies drop aggro (they ignore dead
## targets) instead of trailing the corpse.
func die(_killer: Character) -> void:
	var spawn_position: Vector2 = Vector2.ZERO
	var map: Map = get_parent() as Map
	if map:
		spawn_position = map.get_spawn_position()

	var peer_id: int = int(player_resource.current_peer_id)
	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"player.died", {
			"respawn_in": RESPAWN_DELAY,
			"spawn": spawn_position,
		})

	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(self):
		return # left the game while down

	stats_component.set_stat(Stat.HEALTH, stats_component.get_stat(Stat.HEALTH_MAX))
	is_dead = false


func _set_display_name(new_name: String) -> void:
	display_name = new_name
	if not multiplayer.is_server():
		display_name_changed.emit(new_name)


func is_pvp() -> bool:
	return zone_flags & Map.ZoneMode.PVP


func has_modifier(mod: Map.ZoneModifiers) -> bool:
	var mask: int = 1 << (1 + mod)
	return (zone_flags & mask) != 0


func mark_just_teleported(cooldown_ms: int = 500) -> void:
	teleport_lock_until_ms = Time.get_ticks_msec() + cooldown_ms


func has_recently_teleported() -> bool:
	return Time.get_ticks_msec() < teleport_lock_until_ms
