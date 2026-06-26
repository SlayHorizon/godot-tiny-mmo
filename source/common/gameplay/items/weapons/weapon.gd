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

## Ability count the SCENE shipped (after _ready's duplication) — mastery
## loadout abilities are appended after this index, so remounting can strip
## them without touching scene defaults (the bow/hammer pattern until their
## trees ship).
var _base_ability_count: int = 1

@onready var hand: Hand = $Hand
@onready var weapon_sprite: Sprite2D = $WeaponSprite


## Drives the in-hand sprite from the equipped item's ICON, so a weapon SKIN
## (fire / rustic / ...) is pure item data — NO per-skin scene. The icon is an
## AtlasTexture (same sheet + region the inventory shows), so the in-hand
## sprite always matches the icon by construction. PLACEMENT (offset, centered,
## flip) stays from the weapon-TYPE scene; [param extra_offset] nudges a skin
## whose art sits differently (a taller blade). Client-only — pure visual.
func apply_skin(icon: Texture2D, extra_offset: Vector2 = Vector2.ZERO) -> void:
	if not GameMode.is_client() or weapon_sprite == null or icon is not AtlasTexture:
		return
	var atlas: AtlasTexture = icon as AtlasTexture
	weapon_sprite.texture = atlas.atlas
	weapon_sprite.region_enabled = true
	weapon_sprite.region_rect = atlas.region
	weapon_sprite.position += extra_offset


## Drive the in-hand WeaponSprite from [param icon] — the held item's own icon (a
## consumable or material mounted via Item.mount_in_hand). Client-side only; the
## in-hand sprite is purely cosmetic, so the server skips it.
func show_held_icon(icon: Texture2D) -> void:
	if not GameMode.is_client() or weapon_sprite == null or icon == null:
		return
	if icon is AtlasTexture:
		var atlas: AtlasTexture = icon as AtlasTexture
		weapon_sprite.texture = atlas.atlas
		weapon_sprite.region_enabled = true
		weapon_sprite.region_rect = atlas.region
	else:
		weapon_sprite.texture = icon
		weapon_sprite.region_enabled = false


## Visual hook for a CHANNELED ability (healing aura, future recall): enter/exit
## a "stance" pose while the channel holds. Base does nothing; weapons with a
## distinctive channel look (the hammer planted, swollen, floating) override it.
## Called on EVERY client for the casting player via InstanceClient on the
## channel.start / channel.end push, so the stance shows on allies/enemies too.
func set_channeling_pose(_active: bool) -> void:
	pass


func _ready() -> void:
	if hand and character:
		hand.type = character.hand_type
	# AbilityResources hold per-use state (cooldowns, charge state). If two
	# weapons across two players shared the same .tres they'd share that state —
	# duplicate on equip so each weapon instance owns its abilities outright.
	for i: int in abilities.size():
		if abilities[i] != null:
			abilities[i] = _own_ability(abilities[i])
	_base_ability_count = abilities.size()
	# Register this weapon's animation libraries on the wielder so ability
	# swing_animation names ("weapon/sword.swing", ...) resolve. ONE loader for
	# every weapon — per-weapon scripts must not re-implement this. Idempotent:
	# first equip wins if two weapons share a library name.
	if GameMode.is_client() and character != null:
		for lib_name: StringName in animation_libraries:
			if not character.animation_player.has_animation_library(lib_name):
				character.animation_player.add_animation_library(lib_name, animation_libraries[lib_name])


## Duplicate an ability so this weapon instance owns its per-use state, but TAG it
## with its source path and RESTORE any cooldown the wielder banked for it — so
## re-equipping a weapon can't wipe an in-progress cooldown (the swap-out-and-back
## exploit reset every ability, even 20s ultimates). resource_path is the stable
## key, captured before duplicate() blanks it; inline abilities with no path skip
## persistence (per-instance, as before).
func _own_ability(src: AbilityResource) -> AbilityResource:
	var key: String = src.resource_path
	var copy: AbilityResource = src.duplicate()
	if not key.is_empty():
		copy.set_meta(&"cooldown_key", key)
		if character != null and character.ability_cooldowns.has(key):
			copy.last_action_time = float(character.ability_cooldowns[key])
	return copy


## mark_used + bank the cooldown on the wielder so it survives a re-equip (see
## _own_ability). Used at every ability use site instead of bare mark_used().
func _stamp_cooldown(ability: AbilityResource) -> void:
	ability.mark_used()
	if character != null:
		var key: String = String(ability.get_meta(&"cooldown_key", ""))
		if not key.is_empty():
			character.ability_cooldowns[key] = ability.last_action_time


## Mounts the mastery-chosen special abilities at their PICKED slot positions
## (every machine runs this off the synced special-ability ids — see
## EquipmentComponent). Slot i lands at abilities[_base_ability_count + i], so
## the panel's "Slot 1 (Q) / Slot 2 (E)" labels are always truthful; an empty
## pick leaves a null HOLE (all input/use gates skip nulls) instead of
## shifting later picks onto the wrong key. All-empty ids just strip previous
## loadout mounts — scene-default specials (bow/hammer until their trees
## ship) are untouched.
func mount_specials(ability_ids: Array[int]) -> void:
	var ids: Array[int] = ability_ids.duplicate()
	while not ids.is_empty() and ids[ids.size() - 1] <= 0:
		ids.pop_back() # trailing empties: shrink the array, no pointless holes
	abilities.resize(_base_ability_count)
	if ids.is_empty():
		return
	if ContentRegistryHub.registry_of(&"abilities") == null:
		return # index not generated yet — loadout stays inert
	abilities.resize(_base_ability_count + ids.size())
	for i: int in ids.size():
		if ids[i] <= 0:
			continue # explicit empty slot — leave the null hole
		var ability: AbilityResource = ContentRegistryHub.load_by_id(&"abilities", ids[i]) as AbilityResource
		if ability != null:
			# Same rule as _ready: own the instance outright, but keep its cooldown.
			abilities[_base_ability_count + i] = _own_ability(ability)


## Install a runtime-built ability on the SPECIAL (Q) slot, leaving the PRIMARY
## (left-click) slot empty — used by held non-weapon items (a consumable's "drink") so
## the action is a DELIBERATE Q press / tile tap, never the spammy main attack (stray
## left-clicks would otherwise waste potions). NOT duplicated (the caller made a fresh
## per-mount instance); the [null, ability] shape + _base_ability_count = 2 mean a later
## mount_specials() can't resize it away (the generic hand ships with zero abilities).
func set_special_ability(ability: AbilityResource) -> void:
	abilities = [null, ability]
	_base_ability_count = 2


func try_perform_action(action_index: int, direction: Vector2) -> bool:
	# Negative indices would wrap around the array (Python-style) — reject both ends.
	if action_index < 0 or action_index >= abilities.size():
		return false
	var ability: AbilityResource = abilities[action_index]
	if ability == null or not ability.can_use(character):
		return false
	perform_action(action_index, direction)
	return true


## [param released] selects the phase for two-phase abilities (press begins,
## release fires). Single-phase abilities ignore it.
func can_use_weapon(action_index: int, released: bool = false) -> bool:
	if action_index < 0 or action_index >= abilities.size():
		return false
	if abilities[action_index] == null:
		return false # empty loadout slot (null hole)
	if released:
		return abilities[action_index].has_release and abilities[action_index].can_use_release()
	return abilities[action_index].can_use(character)


func perform_action(action_index: int, direction: Vector2, released: bool = false) -> void:
	if action_index < 0 or action_index >= abilities.size():
		return
	var ability: AbilityResource = abilities[action_index]
	if ability == null:
		return # empty loadout slot (null hole)
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
		_stamp_cooldown(ability)
		_consume_mana(ability)
	else:
		ability.use_ability(character, direction)
		if not ability.has_release:
			_stamp_cooldown(ability)
			_consume_mana(ability)


## Server-authoritative mana payment for a just-completed ability. Clients see
## the new value through the regular stat sync (their HUD bar updates itself).
func _consume_mana(ability: AbilityResource) -> void:
	if ability.mana_cost <= 0 or character == null or not GameMode.is_world_server():
		return
	var mana: float = character.stats_component.get_stat(Stat.MANA)
	character.stats_component.set_stat(Stat.MANA, maxf(0.0, mana - ability.mana_cost))


## A complete one-shot attack for AI / auto use. Routes through the ability's
## auto_use so charge weapons fire at FULL power (an NPC's damage is its
## EnemyTypeResource tuning, not a button-tap minimum).
func auto_attack(direction: Vector2) -> void:
	if abilities.is_empty() or abilities[0] == null:
		return # no primary (a held non-weapon item parks its action on the special slot)
	var ability: AbilityResource = abilities[0]
	if not ability.can_use(character):
		return
	ability.auto_use(character, direction)
	_stamp_cooldown(ability)
	_consume_mana(ability)


func process_input(local_player: LocalPlayer) -> void:
	# primary attack (player_shoot)      → abilities[0]
	# special attack (player_special)    → abilities[1]
	# special 2      (player_special_2)  → abilities[2]
	# Single-phase: tap to fire (predictive local mark_used keeps the channel
	# quiet while held). Two-phase: press sends the charge, release sends the
	# fire — _held bridges the round-trip so a fast tap still releases.
	if abilities.is_empty():
		return
	var controller: InputComponent = local_player.controller
	_handle_slot_input(0, controller.is_attack_just_pressed(), controller.is_attack_just_released(), local_player)
	if abilities.size() > 1:
		_handle_slot_input(1, controller.is_special_just_pressed(), controller.is_special_just_released(), local_player)
	if abilities.size() > 2:
		_handle_slot_input(2, controller.is_special2_just_pressed(), controller.is_special2_just_released(), local_player)


## Fire ability [param slot] directly from a touch ability-bar tap. Mirrors the
## PRESS half of [method process_input]'s input poll (prediction + server send),
## so a tap fires a single-phase ability and a press-and-hold starts charging a
## two-phase one. Aim comes from [member LocalPlayer.look_direction] (the cached
## stick aim), and going direct bypasses the input component's _ui_blocks_combat
## gate — a finger ON the bar would otherwise read as "UI blocks combat".
func press_slot(slot: int, local_player: LocalPlayer) -> void:
	if local_player.is_equip_drawing():
		return # abilities locked mid weapon-draw / drink-cast
	if slot >= 0 and slot < abilities.size():
		_handle_slot_input(slot, true, false, local_player)


## RELEASE half of a touch ability-bar tap — fires a charged two-phase ability;
## a no-op for single-phase ones. Pair with [method press_slot].
func release_slot(slot: int, local_player: LocalPlayer) -> void:
	if slot >= 0 and slot < abilities.size():
		_handle_slot_input(slot, false, true, local_player)


func _handle_slot_input(slot: int, just_pressed: bool, just_released: bool, local_player: LocalPlayer) -> void:
	var ability: AbilityResource = abilities[slot]
	if ability == null:
		return # empty loadout slot (null hole)
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
			_stamp_cooldown(ability) # predictive — server cooldown stays authoritative
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
