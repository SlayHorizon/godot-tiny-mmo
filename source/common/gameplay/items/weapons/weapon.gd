@icon("res://assets/node_icons/blue/icon_sword.png")
class_name Weapon
extends Node2D
## Base weapon: a thin shell around its abilities array. Slot 0 = primary
## (attack input), slot 1 = special. Single-phase abilities fire on press;
## two-phase abilities (ChargeAbility — has_release) begin on press and fire on
## release, carried over the same action.perform wire with an "r" flag. Weapon
## scripts only exist for VISUALS (bow draw frames, hammer slam tween) — all
## gameplay numbers live in the ability .tres files.


@export var abilities: Array[AbilityResource]
@export var animation_libraries: Dictionary[StringName, AnimationLibrary]

var character: Character

## Charge-input prediction: slot -> true while the local player holds a charge
## button, so the release sends even if the server's "began" hasn't echoed back.
var _held: Dictionary[int, bool] = {}

@onready var hand: Hand = $Hand
@onready var weapon_sprite: Sprite2D = $WeaponSprite


func _ready() -> void:
	if hand and character:
		hand.type = character.hand_type
	# AbilityResources hold per-use state (cooldowns, charge state). If two
	# weapons across two players shared the same .tres they'd share that state —
	# duplicate on equip so each weapon instance owns its abilities outright.
	for i: int in abilities.size():
		if abilities[i] != null:
			abilities[i] = abilities[i].duplicate()


func try_perform_action(action_index: int, direction: Vector2) -> bool:
	# Negative indices would wrap around the array (Python-style) — reject both ends.
	if action_index < 0 or action_index >= abilities.size():
		return false
	var ability: AbilityResource = abilities[action_index]
	if not ability.can_use(character):
		return false
	perform_action(action_index, direction)
	return true


## [param released] selects the phase for two-phase abilities (press begins,
## release fires). Single-phase abilities ignore it.
func can_use_weapon(action_index: int, released: bool = false) -> bool:
	if action_index < 0 or action_index >= abilities.size():
		return false
	if released:
		return abilities[action_index].has_release and abilities[action_index].can_use_release()
	return abilities[action_index].can_use(character)


func perform_action(action_index: int, direction: Vector2, released: bool = false) -> void:
	if action_index < 0 or action_index >= abilities.size():
		return
	var ability: AbilityResource = abilities[action_index]
	# Cooldown + mana stamp on the COMPLETING phase: press for single-phase
	# abilities, release for charge abilities. mark_used here (not only in
	# try_perform_action) so the server action.perform path respects cooldowns.
	if released:
		# No can_use_release re-gate here: the SERVER gates via the action.perform
		# handler before calling, and client copies must apply echoes blindly —
		# the local player predicted charging=false at send time, and a remote
		# peer may have missed the begin (releases on a cold copy just fire an
		# uncharged visual, which is correct).
		if not ability.has_release:
			return
		ability.release_ability(character, direction)
		ability.mark_used()
		_consume_mana(ability)
	else:
		ability.use_ability(character, direction)
		if not ability.has_release:
			ability.mark_used()
			_consume_mana(ability)


## Server-authoritative mana payment for a just-completed ability. Clients see
## the new value through the regular stat sync (their HUD bar updates itself).
func _consume_mana(ability: AbilityResource) -> void:
	if ability.mana_cost <= 0 or character == null or not GameMode.is_world_server():
		return
	var mana: float = character.stats_component.get_stat(Stat.MANA)
	character.stats_component.set_stat(Stat.MANA, maxf(0.0, mana - ability.mana_cost))


## A complete one-shot attack for AI / auto use. For charge abilities the
## release follows instantly — an uncharged (minimum) shot, which is the right
## NPC behavior (their damage is tuned on the EnemyTypeResource anyway).
func auto_attack(direction: Vector2) -> void:
	if abilities.is_empty():
		return
	perform_action(0, direction)
	if abilities[0].has_release:
		perform_action(0, direction, true)


func process_input(local_player: LocalPlayer) -> void:
	# primary attack (player_shoot)   → abilities[0]
	# special attack (player_special) → abilities[1]
	# Single-phase: tap to fire (predictive local mark_used keeps the channel
	# quiet while held). Two-phase: press sends the charge, release sends the
	# fire — _held bridges the round-trip so a fast tap still releases.
	if abilities.is_empty():
		return
	var controller: InputComponent = local_player.controller
	_handle_slot_input(0, controller.is_attack_just_pressed(), controller.is_attack_just_released(), local_player)
	if abilities.size() > 1:
		_handle_slot_input(1, controller.is_special_just_pressed(), controller.is_special_just_released(), local_player)


func _handle_slot_input(slot: int, just_pressed: bool, just_released: bool, local_player: LocalPlayer) -> void:
	var ability: AbilityResource = abilities[slot]
	if just_pressed and ability.can_use(character):
		if ability.has_release:
			_held[slot] = true
			# Predictive press: a charge-press has no effects (it just flips
			# state), so run it locally NOW. This silences the LocalPlayer
			# hold-to-attack loop instantly instead of letting it flood the
			# server until the echo arrives (the flood tripped the rate
			# limiter, which ate releases and bricked the bow).
			ability.use_ability(character, Vector2.ZERO)
		else:
			ability.mark_used() # predictive — server cooldown stays authoritative
		_send_action(slot, false, local_player)
	# Independent `if` (NOT elif): a fast tap can press and release within the
	# same frame — the release must still send or the shot never fires.
	# Gate on _held OR local charging so a desynced flag can't strand the bow.
	if just_released and ability.has_release and (_held.get(slot, false) or ability.can_use_release()):
		_held[slot] = false
		# Predictive release: flip local state at send time — never wait for
		# the echo (a lost echo would strand "charging" forever).
		ability.predict_release()
		_send_action(slot, true, local_player)


func _send_action(slot: int, released: bool, local_player: LocalPlayer) -> void:
	var args: Dictionary = {"d": local_player.look_direction, "i": slot}
	if released:
		args["r"] = true
	Client.request_data(&"action.perform", Callable(), args, InstanceClient.current.name)
