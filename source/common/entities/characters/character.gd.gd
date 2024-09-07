@icon("res://assets/node_icons/blue/icon_character.png")
class_name Character
extends Entity
## Class for all characters (Player, 
enum Animations {
	IDLE,
	RUN,
	DEATH,
}

#const POSSIBLE_SYNC := ["position", "sprite_frames", "anim", "flipped"]

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var sprite_frames: String = "knight":
	set = _set_sprite_frames

var anim: Animations = Animations.IDLE:
	set = _set_anim

var flipped: bool = false:
	set = _set_flip

func _set_sprite_frames(new_sprite_frames: String) -> void:
	animated_sprite.sprite_frames = ResourceLoader.load(
		"res://source/common/resources/builtin/sprite_frames/" + new_sprite_frames + ".tres")

func _set_anim(new_anim: Animations) -> void:
	match new_anim:
		Animations.IDLE:
			animated_sprite.play("idle")
		Animations.RUN:
			animated_sprite.play("run")
		Animations.DEATH:
			animated_sprite.play("death")
	anim = new_anim

func _set_flip(new_flip: bool) -> void:
	flipped = new_flip
	animated_sprite.flip_h = flipped

func _set_sync_state(new_state: Dictionary) -> void:
	sync_state = new_state
	for property: String in new_state:
		set(property, new_state[property])

func _set_spawn_state(new_state: Dictionary) -> void:
	spawn_state = new_state
	if not is_node_ready():
		await ready
	for property: String in new_state:
		set(property, new_state[property])
