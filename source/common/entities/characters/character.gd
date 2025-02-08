@icon("res://assets/node_icons/blue/icon_character.png")
class_name Character
extends Entity


enum Animations {
	IDLE,
	RUN,
	DEATH,
}

var hand_type: Hand.Types

var weapon_name_right: String:
	set = _set_right_weapon
var weapon_name_left: String:
	set = _set_left_weapon
var equiped_weapon_right: Weapon
var equiped_weapon_left: Weapon

var sprite_frames: String = "knight":
	set = _set_sprite_frames

var anim: Animations = Animations.IDLE:
	set = _set_anim

var flipped: bool = false:
	set = _set_flip

var pivot: float = 0.0:
	set = _set_pivot

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hand_offset: Node2D = $HandOffset
@onready var hand_pivot: Node2D = $HandOffset/HandPivot

@onready var right_hand_spot: Node2D = $HandOffset/HandPivot/RightHandSpot
@onready var left_hand_spot: Node2D = $HandOffset/HandPivot/LeftHandSpot


func _ready() -> void:
	if right_hand_spot.get_child_count():
		equiped_weapon_right = right_hand_spot.get_child(0)
		equiped_weapon_right.hand.type = hand_type
		equiped_weapon_right.hand.side = Hand.Sides.RIGHT
	if left_hand_spot.get_child_count():
		equiped_weapon_left = left_hand_spot.get_child(0)
		equiped_weapon_right.hand.type = hand_type
		equiped_weapon_right.hand.side = Hand.Sides.LEFT


func change_weapon(weapon_path: String, _side: bool = true) -> void:
	if equiped_weapon_right:
		equiped_weapon_right.queue_free()
	var new_weapon: Weapon = load("res://source/common/items/weapons/" + 
		weapon_path + ".tscn").instantiate()
	new_weapon.character = self
	right_hand_spot.add_child(new_weapon)
	equiped_weapon_right = new_weapon


func update_weapon_animation(state: String) -> void:
	equiped_weapon_right.play_animation(state)
	equiped_weapon_left.play_animation(state)


func _set_left_weapon(weapon_name: String) -> void:
	weapon_name_left = weapon_name
	change_weapon(weapon_name, false)


func _set_right_weapon(weapon_name: String) -> void:
	weapon_name_right = weapon_name
	change_weapon(weapon_name, true)


func _set_sprite_frames(new_sprite_frames: String) -> void:
	animated_sprite.sprite_frames = ResourceLoader.load(
		"res://source/common/resources/builtin/sprite_frames/" + new_sprite_frames + ".tres"
	)


func _set_anim(new_anim: Animations) -> void:
	match new_anim:
		Animations.IDLE:
			animated_sprite.play("idle")
			update_weapon_animation("idle")
		Animations.RUN:
			animated_sprite.play("run")
			update_weapon_animation("run")
		Animations.DEATH:
			animated_sprite.play("death")
	anim = new_anim


func _set_flip(new_flip: bool) -> void:
	animated_sprite.flip_h = new_flip
	hand_offset.scale.x = -1 if new_flip else 1
	flipped = new_flip


func _set_pivot(new_pivot: float) -> void:
	pivot = new_pivot
	hand_pivot.rotation = new_pivot


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
