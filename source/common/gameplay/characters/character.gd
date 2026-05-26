@icon("res://assets/node_icons/blue/icon_character.png")
class_name Character
extends Entity


enum Animations {
	IDLE,
	RUN,
	DEATH,
}

var hand_type: Hand.Types

var skin_id: int:
	set = _set_skin_id

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
@onready var stats_component: StatsComponent = $StatsComponent
@onready var equipment_component: EquipmentComponent = $EquipmentComponent
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var locomotion_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/OnFoot/LocomotionSM/playback")
@onready var weapon_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/OnFoot/WeaponSM/playback")


func _ready() -> void:
	if multiplayer.is_server():
		return
	_on_stat_changed(Stat.HEALTH, stats_component.get_stat(Stat.HEALTH))
	_on_stat_changed(Stat.HEALTH_MAX, stats_component.get_stat(Stat.HEALTH_MAX))
	stats_component.stats.stat_changed.connect(_on_stat_changed)


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.HEALTH:
		$ProgressBar.value = value
	if stat_name == Stat.HEALTH_MAX:
		$ProgressBar.max_value = value


# --- Combat (server-authoritative) ---

## True once health has hit zero, until the subclass revives/respawns.
var is_dead: bool = false
## The character that dealt the most recent damage (for kill attribution).
var last_attacker: Character


## Server-only. Applies [param amount] raw damage from [param attacker], mitigated by
## the target's ARMOR, then triggers death at zero health. Every attack (projectiles,
## melee, NPC hits) routes through here so damage/death/attribution live in one place.
func take_damage(amount: float, attacker: Character = null) -> void:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return
	if attacker:
		last_attacker = attacker

	var armor: float = stats_component.get_stat(Stat.ARMOR)
	var mitigated: float = amount * (100.0 / (100.0 + maxf(0.0, armor)))
	var new_health: float = maxf(0.0, stats_component.get_stat(Stat.HEALTH) - mitigated)
	stats_component.set_stat(Stat.HEALTH, new_health)

	if new_health <= 0.0:
		is_dead = true
		die(attacker)


## Overridden by Player (respawn) and HostileNpc (reward + respawn). Base does nothing.
func die(_killer: Character) -> void:
	pass


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
