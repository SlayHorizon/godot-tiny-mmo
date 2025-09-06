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
var equipped_weapon_right: Weapon
var equipped_weapon_left: Weapon

var character_class: String:
	set = _set_character_class
var character_resource: CharacterResource

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

@onready var state_synchronizer: StateSynchronizer = $StateSynchronizer
@onready var ability_system_component: AbilitySystemComponent = $AbilitySystemComponent
@onready var equipment_component: EquipmentComponent = $EquipmentComponent


func _ready() -> void:
	# NEW
	$AbilitySystemComponent/AttributesMirror.attribute_local_changed.connect(
		func(attr: StringName, value: float, max_value: float):
			#print(attr, " value = ", value, " max_value = ", max_value)
			if attr != &"health":
				return
			$ProgressBar.value = value
			$ProgressBar.max_value = max_value
	)
	
	# OLD
	if right_hand_spot.get_child_count():
		equipped_weapon_right = right_hand_spot.get_child(0)
		equipped_weapon_right.hand.type = hand_type
		equipped_weapon_right.hand.side = Hand.Sides.RIGHT
		equipped_weapon_right.character = self
	if left_hand_spot.get_child_count():
		equipped_weapon_left = left_hand_spot.get_child(0)
		equipped_weapon_right.hand.type = hand_type
		equipped_weapon_right.hand.side = Hand.Sides.LEFT
		equipped_weapon_left.character = self


func change_weapon(weapon_path: String, _side: bool = true) -> void:
	if equipped_weapon_right:
		equipped_weapon_right.queue_free()
	var new_weapon: Weapon = load("res://source/common/gameplay/items/weapons/" + 
		weapon_path + ".tscn").instantiate()
	new_weapon.character = self
	right_hand_spot.add_child(new_weapon)
	equipped_weapon_right = new_weapon


func update_weapon_animation(state: String) -> void:
	equipped_weapon_right.play_animation(state)
	equipped_weapon_left.play_animation(state)


func _set_left_weapon(weapon_name: String) -> void:
	weapon_name_left = weapon_name
	change_weapon(weapon_name, false)


func _set_right_weapon(weapon_name: String) -> void:
	weapon_name_right = weapon_name
	change_weapon(weapon_name, true)


func _set_sprite_frames(new_sprite_frames: String) -> void:
	animated_sprite.sprite_frames = ResourceLoader.load(
		"res://source/common/gameplay/characters/sprite_frames/" + new_sprite_frames + ".tres"
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


func _set_character_class(new_class: String):
	character_resource = ResourceLoader.load(
		"res://source/common/gameplay/characters/classes/character_collection/" + new_class + ".tres")
	animated_sprite.sprite_frames = character_resource.character_sprite
	character_class = new_class
