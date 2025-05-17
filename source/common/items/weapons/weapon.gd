@icon("res://assets/node_icons/blue/icon_sword.png")
class_name Weapon
extends Node2D


@export var has_custom_idle: bool = false
@export var has_custom_walk: bool = false
@export var abilities: Array[AbilityResource]

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


## To override
var timer: Timer

func weapon_action(action_index: int, action_direction: Vector2) -> bool:
	if OS.has_feature("world-server"):
		if not timer:
			timer = Timer.new()
			timer.wait_time = 0.5
			timer.one_shot = true
			add_child(timer)
			timer.start()
		if timer.time_left > 0:
			return false
		else:
			timer.start()
	if action_index == 0:
		var arrow: Area2D = load("res://source/common/items/weapons/bow/arrow.tscn").instantiate()
		arrow.top_level = true
		arrow.direction = action_direction
		arrow.global_position = global_position
		add_child(arrow)
		return true
	return false


# --- Try to execute action (server or client-predicted)
func try_perform_action(action_index: int, direction: Vector2) -> bool:
	if action_index >= abilities.size():
		return false

	var ability: AbilityResource = abilities[action_index]

	if not ability.can_use():
		return false

	# Call ability logic
	ability.use_ability(self, direction)

	# Mark cooldown
	ability.mark_used()

	return true

# --- To be overridden by specific weapons
func perform_action(action_index: int, direction: Vector2) -> void:
	if action_index == 0:
		var arrow: Area2D = preload("res://source/common/items/weapons/bow/arrow.tscn").instantiate()
		arrow.top_level = true
		arrow.direction = direction
		arrow.global_position = global_position
		get_tree().current_scene.add_child(arrow)
