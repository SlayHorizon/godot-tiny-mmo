@icon("res://assets/node_icons/blue/icon_sword.png")
class_name Weapon
extends Node2D


@export var abilities: Array[AbilityResource]

var character: Character

@onready var hand: Hand = $Hand
@onready var weapon_sprite: Sprite2D = $WeaponSprite
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	if hand and character:
		hand.type = character.hand_type


func play_animation(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)


func try_perform_action(action_index: int, direction: Vector2) -> bool:
	if action_index >= abilities.size():
		return false

	var ability: AbilityResource = abilities[action_index]

	if not ability.can_use():
		return false

	# Call ability logic
	ability.use_ability(owner, direction)

	# Mark cooldown
	ability.mark_used()

	return true
