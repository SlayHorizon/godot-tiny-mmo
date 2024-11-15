extends Button


var world_id: int = 0


@onready var server_name: Label = $VBoxContainer/ServerName
@onready var server_rules: Label = $VBoxContainer/ServerRules
@onready var server_location: Label = $VBoxContainer/ServerLocation


func apply_world_info(world_info: Dictionary) -> void:
	server_name.text = world_info["name"]
	server_rules.text = "Bonus XP: %d\nPVP: %s\nHardcore: %s" % [
		world_info["bonus_xp"], world_info["pvp"], world_info["hardcore"]
	]
