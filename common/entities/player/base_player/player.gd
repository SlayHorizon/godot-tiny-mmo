class_name Player
extends Entity

# Incomplete
var player_resource: PlayerResource
var equiped_item: ItemResource

var display_name: String = "Player":
	set = _set_display_name

var animation: String = "idle":
	set = _set_animation

var direction: bool = false:
	set = _set_direction

var sprite_frames: String = "knight":
	set = _set_sprite_frames

var is_in_pvp_zone: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _init() -> void:
	sync_state = {"T" = 0.0}
	group = Group.PLAYER

func _set_display_name(_new_name: String) -> void:
	pass

func _set_animation(new_animation: String) -> void:
	animation = new_animation
	animated_sprite.play(new_animation)

func _set_direction(new_direction: bool) -> void:
	direction = new_direction
	animated_sprite.flip_h = direction

func _set_sprite_frames(new_sprite_frames: String) -> void:
	# Bad design, not scalable and optimized
	match new_sprite_frames:
		"knight":
			animated_sprite.sprite_frames = load("res://common/resources/builtin/sprite_frames_collection/knight.tres")
		"rogue":
			animated_sprite.sprite_frames = load("res://common/resources/builtin/sprite_frames_collection/rogue.tres")
		"wizard":
			animated_sprite.sprite_frames = load("res://common/resources/builtin/sprite_frames_collection/wizard.tres")

func _set_sync_state(new_state) -> void:
	sync_state = new_state
	for property: String in new_state:
		set(property, new_state[property])

func _set_spawn_state(new_state) -> void:
	spawn_state = new_state
	if not is_node_ready():
		await ready
	for property: String in new_state:
		set(property, new_state[property])
