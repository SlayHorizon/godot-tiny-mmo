@icon("res://assets/node_icons/blue/icon_character.png")
class_name Character
extends Entity


signal display_name_changed(new_name: String)

enum Animations {
	IDLE,
	RUN,
	DEATH,
}

var hand_type: Hand.Types

var skin_id: int:
	set = _set_skin_id

var display_name: String = "Unknown":
	set = _set_display_name

var anim: Animations = Animations.IDLE:
	set = _set_anim

var flipped: bool = false:
	set = _set_flip

var pivot: float = 0.0:
	set = _set_pivot

## Per-ability cooldown memory (resource_path -> last_action_time seconds), banked
## by the weapon on use and restored when an ability is (re)mounted — so swapping a
## weapon out and back can't wipe cooldowns. Transient (per session); each machine
## keeps its own (server authoritative, the client mirrors it for prediction).
var ability_cooldowns: Dictionary = {}

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hand_offset: Node2D = $HandOffset
@onready var hand_pivot: Node2D = $HandOffset/HandPivot

@onready var right_hand_spot: Node2D = $HandOffset/HandPivot/RightHandSpot
@onready var left_hand_spot: Node2D = $HandOffset/HandPivot/LeftHandSpot

@onready var state_synchronizer: StateSynchronizer = $StateSynchronizer
@onready var stats_component: StatsComponent = $StatsComponent
@onready var equipment_component: EquipmentComponent = $EquipmentComponent
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var locomotion_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/OnFoot/LocomotionSM/playback")
@onready var weapon_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/OnFoot/WeaponSM/playback")


## Over-head HP bar fill colors by relationship to the local viewer. Missing HP
## shows the bar's dark background. Subclasses recolor on _ready / guild change.
const BAR_COLOR_SELF: Color = Color(0.38, 0.82, 0.42)    # you
const BAR_COLOR_ALLY: Color = Color(0.30, 0.62, 1.0)     # guildmate / guard
const BAR_COLOR_NEUTRAL: Color = Color(0.82, 0.82, 0.86) # other players
const BAR_COLOR_HOSTILE: Color = Color(0.86, 0.33, 0.28) # mobs / default

## The local viewer's tagged guild, mirrored here from ClientState. Static so
## Player can read it WITHOUT referencing ClientState — that reference would close
## a ClientState → LocalPlayer → Player → ClientState compile cycle.
static var local_viewer_guild_id: int = 0

## Peer ids of the local player's CURRENT spar teammates / opponents (empty when
## not in a match). Same static-mirror pattern as local_viewer_guild_id; set by
## LocalPlayer from the sparring.match.state push. While a match is live these
## override guild colors on health bars — an opposing guildmate reads hostile.
static var spar_ally_peers: Array = []
static var spar_opponent_peers: Array = []

## Peer ids of the local player's CURRENT co-op group (empty when not grouped) —
## the dungeon allegiance, mirrored client-side from the group.roster push, same
## pattern as spar peers. Groupmates read as allies regardless of guild.
static var group_peers: Array = []


func _ready() -> void:
	if multiplayer.is_server():
		return
	_on_stat_changed(Stat.HEALTH, stats_component.get_stat(Stat.HEALTH))
	_on_stat_changed(Stat.HEALTH_MAX, stats_component.get_stat(Stat.HEALTH_MAX))
	stats_component.stats.stat_changed.connect(_on_stat_changed)
	set_health_bar_fill(BAR_COLOR_HOSTILE) # default; subclasses recolor by team


## Client: paint the over-head HP bar fill a solid color. Always SET (never
## remove the override — that reverts to the theme's gray default). Square,
## anti-aliasing off so edges stay crisp on a low-res pixel-art canvas.
func set_health_bar_fill(color: Color) -> void:
	if not has_node(^"ProgressBar"):
		return
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.anti_aliasing = false
	($ProgressBar as ProgressBar).add_theme_stylebox_override(&"fill", fill)


# --- Hit-feedback state (client-side only) -----------------------------------
## Last seen HEALTH value, used to detect *decreases* so we only trigger hit
## feedback on incoming damage, never on regen / respawn / heals.
var _last_health_seen: float = -1.0
## Sound path played on each hit. Spatial — SfxPool culls distance via the
## LocalPlayer's position so off-screen hits don't make noise. Drop the
## file under this path later and it'll just start working.
const HIT_SOUND_PATH: String = "res://assets/audio/sfx/hit.wav"
## How long the red-tint flash lasts on hit. Two-phase: snap to red (short),
## fade back to white (longer). The snap reads as "impact", the fade lets
## back-to-back hits stack readably.
const HIT_FLASH_SNAP_S: float = 0.05
const HIT_FLASH_FADE_S: float = 0.18

var _hit_flash_tween: Tween


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.HEALTH:
		$ProgressBar.value = value
		# Hit feedback fires on net HP decrease only — regen, idle-heal,
		# respawn-snap-to-full would otherwise spam flash/sound.
		if _last_health_seen >= 0.0 and value < _last_health_seen:
			_play_hit_feedback()
		_last_health_seen = value
	if stat_name == Stat.HEALTH_MAX:
		$ProgressBar.max_value = value


## Combat juice: brief red tint on the sprite + a spatial hit SFX. Called
## from _on_stat_changed when this character's HEALTH ticks down. No-op if
## we're on the server (this whole region is gated by Character._ready).
func _play_hit_feedback() -> void:
	# Sprite flash: snap-bright red, fade back to neutral. modulate values
	# above 1.0 brighten (multiplier), so (2.0, 0.5, 0.5) reads as a stark
	# red pulse rather than a flat red overlay.
	if animated_sprite != null:
		if _hit_flash_tween != null and _hit_flash_tween.is_running():
			_hit_flash_tween.kill()
		_hit_flash_tween = create_tween()
		_hit_flash_tween.tween_property(animated_sprite, ^"modulate", Color(2.0, 0.5, 0.5, 1.0), HIT_FLASH_SNAP_S)
		_hit_flash_tween.tween_property(animated_sprite, ^"modulate", Color.WHITE, HIT_FLASH_FADE_S)

	# Spatial hit sound. The SfxPool short-circuits if the LocalPlayer is
	# out of audible range, so a hit happening across the map is silent.
	if is_instance_valid(Client) and Client.audio_manager != null:
		Client.audio_manager.play_sfx(HIT_SOUND_PATH, global_position)


# --- Combat (server-authoritative) ---

## True once health has hit zero, until the subclass revives/respawns.
var is_dead: bool = false
## The character that dealt the most recent damage (for kill attribution).
var last_attacker: Character

## How long a hit (dealt OR taken) keeps a combatant "in combat". Gear swaps
## are locked while in combat so you can't re-spec mid-fight.
const COMBAT_LINGER_MS: int = 5000
## Server-side runtime: ticks_msec until which this character counts as in
## combat. Set on every hit for both attacker and victim.
var combat_until_ms: int = 0


## Server-side: true while a recent hit still keeps this character in combat.
func is_in_combat() -> bool:
	return Time.get_ticks_msec() < combat_until_ms


## Server-only. Applies [param amount] raw damage from [param attacker], mitigated by
## the matching resistance — ARMOR for physical, MR for magic (see CombatHit's
## damage-type constants) — then triggers death at zero health. Every attack
## (projectiles, melee, NPC hits) routes through here so damage/death/attribution
## live in one place.
func take_damage(amount: float, attacker: Character = null, damage_type: StringName = CombatHit.DAMAGE_PHYSICAL) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	# Any landed hit puts BOTH sides in combat (locks gear swaps for a few
	# seconds): the victim here, and the attacker so they can't tag-and-swap.
	var now: int = Time.get_ticks_msec()
	combat_until_ms = now + COMBAT_LINGER_MS
	if attacker:
		last_attacker = attacker
		attacker.combat_until_ms = now + COMBAT_LINGER_MS

	var resist_stat: StringName = Stat.MR if damage_type == CombatHit.DAMAGE_MAGIC else Stat.ARMOR
	var resist: float = stats_component.get_stat(resist_stat)
	var mitigated: float = amount * (100.0 / (100.0 + maxf(0.0, resist)))
	var new_health: float = maxf(0.0, stats_component.get_stat(Stat.HEALTH) - mitigated)
	stats_component.set_stat(Stat.HEALTH, new_health)

	# Broadcast a hit event so clients can render damage numbers, screen
	# shake, hit pause, sound — anything game-feel piggybacks off the same
	# server push. We send the post-mitigation number so what players see
	# matches the HP actually lost.
	_broadcast_hit_feedback(mitigated)

	if new_health <= 0.0:
		is_dead = true
		die(attacker)


## Wraps the combat.hit push so child classes (Player / NPC / future
## buildings) don't each have to know how to find their ServerInstance.
## Pushes via WorldServer.curr (its static var is stubbed on client exports,
## so common/ can reference it without importing server-only types).
func _broadcast_hit_feedback(mitigated_amount: float) -> void:
	if mitigated_amount <= 0.0 or WorldServer.curr == null:
		return
	# Character is parented under Map, which is parented under ServerInstance.
	# Walk up two steps to find the instance to scope the broadcast to. We
	# don't type-check ServerInstance here because common-side code mustn't
	# import server-only classes — propagate_rpc just needs the instance
	# name (a String) and gracefully falls back if not found.
	var maybe_map: Node = get_parent()
	if maybe_map == null:
		return
	var maybe_instance: Node = maybe_map.get_parent()
	if maybe_instance == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"combat.hit", {
			"amount": int(round(mitigated_amount)),
			"position": global_position,
		}),
		maybe_instance.name
	)


## Overridden by Player (respawn) and HostileNpc (reward + respawn). Base does nothing.
func die(_killer: Character) -> void:
	pass


## Plays a short "action" animation (weapon swing, charge, cast — anything
## abilities want to surface visually). Stamps the animation name into the
## InteruptAnimation slot and triggers InteruptShot, which is the only
## branch of the AnimationTree currently routed to the output.
##
## anim_name uses Godot's library/animation form, e.g. &"weapon/sword.swing".
## The animation must have been added to the AnimationPlayer first — weapons
## do this on equip via add_animation_library.
##
## Server-side is a no-op; animation work is purely cosmetic.
func play_action_animation(anim_name: StringName) -> void:
	if not GameMode.is_client() or anim_name.is_empty():
		return
	if animation_tree == null or animation_tree.tree_root == null:
		return
	# tree_root is a StateMachine; OnFoot is the BlendTree state we author in.
	var on_foot: AnimationNodeBlendTree = animation_tree.tree_root.get_node(&"OnFoot") as AnimationNodeBlendTree
	if on_foot == null:
		return
	var interrupt_anim: AnimationNodeAnimation = on_foot.get_node(&"InteruptAnimation") as AnimationNodeAnimation
	if interrupt_anim == null:
		return
	interrupt_anim.animation = anim_name
	animation_tree[&"parameters/OnFoot/InteruptShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func update_weapon_animation(state: String) -> void:
	pass
	#$AnimationTree.set("parameters/OnFoot/Blend2/blend_amount", 1.0)
	#equipped_weapon_right.play_animation(state)
	#equipped_weapon_left.play_animation(state)


func _set_skin_id(id: int) -> void:
	skin_id = id
	# Avoid uncessary load on server
	if multiplayer.is_server():
		return
	var sprite_frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", id) as SpriteFrames
	if sprite_frames:
		animated_sprite.sprite_frames = sprite_frames


func _set_anim(new_anim: Animations) -> void:
	match new_anim:
		Animations.IDLE:
			locomotion_state_machine.travel(&"locomotion_idle")
		Animations.RUN:
			locomotion_state_machine.travel(&"locomotion_run")
		Animations.DEATH:
			locomotion_state_machine.travel(&"locomotion_death")
	anim = new_anim


func _set_flip(new_flip: bool) -> void:
	animated_sprite.flip_h = new_flip
	hand_offset.scale.x = -1 if new_flip else 1
	flipped = new_flip


func _set_pivot(new_pivot: float) -> void:
	pivot = new_pivot
	hand_pivot.rotation = new_pivot


func _set_display_name(new_name: String) -> void:
	display_name = new_name
	if not multiplayer.is_server():
		display_name_changed.emit(new_name)
