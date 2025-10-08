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
