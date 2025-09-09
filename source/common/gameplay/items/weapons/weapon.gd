@icon("res://assets/node_icons/blue/icon_sword.png")
class_name Weapon
extends Node2D


@export var abilities: Array[AbilityResource]
@export var animation_libraries: Dictionary[StringName, AnimationLibrary]

var character: Character

@onready var hand: Hand = $Hand
@onready var weapon_sprite: Sprite2D = $WeaponSprite


func _ready() -> void:
	if hand and character:
		hand.type = character.hand_type


#func play_animation(anim_name: String) -> void:
	#if animation_player.has_animation(anim_name):
		#animation_player.play(anim_name)


func try_perform_action(action_index: int, direction: Vector2) -> bool:
	if action_index >= abilities.size():
		return false
	
	var ability: AbilityResource = abilities[action_index]
	
	if not ability.can_use():
		return false
	
	ability.use_ability(character, direction)
	
	ability.mark_used()
	
	return true


func can_use_weapon(action_index: int) -> bool:
	if action_index >= abilities.size():
		return false
	return abilities[action_index].can_use()


func perform_action(action_index: int, direction: Vector2) -> void:
	if action_index >= abilities.size():
		return
	abilities[action_index].use_ability(character, direction)
