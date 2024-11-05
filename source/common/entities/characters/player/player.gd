class_name Player
extends Character


var character_class: String:
	set = _set_character_class
var character_resource: CharacterResource
# Unused
var player_resource: PlayerResource

var display_name: String = "Unknown":
	set = _set_display_name

var is_in_pvp_zone: bool = false
var just_teleported: bool = false:
	set(value):
		just_teleported = value
		if not is_inside_tree():
			await tree_entered
		if just_teleported:
			await get_tree().create_timer(0.5).timeout
			just_teleported = false

@onready var display_name_label: Label = $DisplayNameLabel


func _init() -> void:
	sync_state = {"T" = 0.0}
	group = Group.PLAYER


func _set_character_class(new_class: String):
	character_resource = ResourceLoader.load(
		"res://source/common/resources/custom/character/character_collection/" + new_class + ".tres")
	animated_sprite.sprite_frames = character_resource.character_sprite
	character_class = new_class


func _set_display_name(new_name: String) -> void:
	display_name_label.text = new_name
	display_name = new_name


func _set_sync_state(new_state: Dictionary) -> void:
	sync_state = new_state
	for property: String in new_state:
		set(property, new_state[property])
