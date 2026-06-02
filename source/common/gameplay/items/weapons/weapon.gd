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
	# AbilityResources hold per-use state (last_action_time for cooldown
	# tracking). If two weapons across two players share the same .tres,
	# they'd share cooldowns through the resource — bad. Duplicate on equip
	# so each weapon instance owns its abilities outright.
	for i: int in abilities.size():
		if abilities[i] != null:
			abilities[i] = abilities[i].duplicate()


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
	# Animation + side-effects, then stamp the cooldown. mark_used inside
	# perform_action (not just inside try_perform_action) so the server
	# action.perform handler — which goes through perform_action directly —
	# still respects cooldowns.
	abilities[action_index].use_ability(character, direction)
	abilities[action_index].mark_used()


## A complete one-shot attack for AI / auto use. Players may drive multi-step inputs
## (e.g. bow charge/release) directly; this gives NPCs a single "just attack" entry point.
## Default fires action 0; weapons with a charge step (bow) override this.
func auto_attack(direction: Vector2) -> void:
	perform_action(0, direction)


func process_input(local_player: LocalPlayer) -> void:
	# Default: tap-to-fire mapped to ability slots.
	#   primary attack (player_shoot)   → abilities[0]
	#   special attack (player_special) → abilities[1]
	# Weapons with multi-phase inputs (the bow's charge/release) override
	# this. Predictive cooldown bumps locally so LocalPlayer.process_input
	# doesn't re-fire while the button stays held — server cooldown is
	# authoritative, this just keeps the network channel quiet.
	if abilities.is_empty():
		return
	var controller: InputComponent = local_player.controller

	if controller.is_attack_just_pressed() and can_use_weapon(0):
		abilities[0].mark_used()
		Client.request_data(
			&"action.perform",
			Callable(),
			{"d": local_player.look_direction, "i": 0},
			InstanceClient.current.name
		)

	if abilities.size() > 1 and controller.is_special_just_pressed() and can_use_weapon(1):
		abilities[1].mark_used()
		Client.request_data(
			&"action.perform",
			Callable(),
			{"d": local_player.look_direction, "i": 1},
			InstanceClient.current.name
		)
