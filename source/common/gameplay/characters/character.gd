@icon("res://assets/node_icons/blue/icon_character.png")
class_name Character
extends Entity


enum Animations {
	IDLE,
	RUN,
	DEATH,
}

var hand_type: Hand.Types

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
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = $AnimationTree.get("parameters/OnFoot/LocomotionSM/playback")


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


func update_weapon_animation(state: String) -> void:
	pass
	#$AnimationTree.set("parameters/OnFoot/Blend2/blend_amount", 1.0)
	#equipped_weapon_right.play_animation(state)
	#equipped_weapon_left.play_animation(state)


func _set_sprite_frames(new_sprite_frames: String) -> void:
	animated_sprite.sprite_frames = ResourceLoader.load(
		"res://source/common/gameplay/characters/sprite_frames/" + new_sprite_frames + ".tres"
	)


func _set_anim(new_anim: Animations) -> void:
	match new_anim:
		Animations.IDLE:
			state_machine.travel(&"locomotion_idle")
		Animations.RUN:
			state_machine.travel(&"locomotion_run")
		Animations.DEATH:
			state_machine[&"parameters/OnFoot/InteruptShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
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
