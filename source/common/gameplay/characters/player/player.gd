class_name Player
extends Character


var player_resource: PlayerResource

var display_name: String = "Unknown":
	set = _set_display_name

var zone_flags: int = 0
func is_pvp() -> bool: return (zone_flags & 1) != 0
func has_modifier(mod: int) -> bool:
	var mask: int = 1 << (1 + mod)
	return (zone_flags & mask) != 0
var just_teleported: bool = false:
	set(value):
		just_teleported = value
		if not is_inside_tree():
			await tree_entered
		if just_teleported:
			await get_tree().create_timer(0.5).timeout
			just_teleported = false

@onready var syn: StateSynchronizer = $StateSynchronizer
@onready var display_name_label: Label = $DisplayNameLabel


func _init() -> void:
	pass


func _set_display_name(new_name: String) -> void:
	display_name_label.text = new_name
	display_name = new_name
