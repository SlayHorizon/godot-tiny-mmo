@icon("res://assets/node_icons/blue/icon_sword.png")
class_name Weapon
extends Node2D


@export var has_custom_idle: bool = false
@export var has_custom_walk: bool = false

var character: Character

@onready var hand: Hand = $Hand
@onready var weapon_sprite: Sprite2D = $WeaponSprite
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	if hand and character:
		hand.type = character.hand_type
	if animation_player.has_animation("custom/idle"):
		has_custom_idle = true
	if animation_player.has_animation("custom/walk"):
		has_custom_walk = true


func play_animation(anim_name: String) -> void:
	# Bad design
	if anim_name == "idle":
		if has_custom_idle:
			animation_player.play("custom/idle")
		else:
			animation_player.play("idle")
	if anim_name == "walk":
		if has_custom_idle:
			animation_player.play("custom/walk")
		else:
			animation_player.play("walk")
