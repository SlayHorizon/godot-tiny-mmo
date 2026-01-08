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
@onready var ability_system_component: AbilitySystemComponent = $AbilitySystemComponent
@onready var equipment_component: EquipmentComponent = $EquipmentComponent
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var locomotion_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/OnFoot/LocomotionSM/playback")
@onready var weapon_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/OnFoot/WeaponSM/playback")


var is_dead: bool = false


func _ready() -> void:
	if multiplayer.is_server():
		# Server-side: connect health watcher for death detection
		ability_system_component.connect_watcher(Stat.HEALTH, _on_health_changed)
		return
	
	# Client-side: connect health watchers for UI updates
	ability_system_component.connect_watcher(Stat.HEALTH, _on_client_health_changed)
	ability_system_component.connect_watcher(Stat.HEALTH_MAX, _on_client_health_max_changed)
	
	# Ensure health bar is initialized with current values
	call_deferred("_update_health_bar_from_sync")


func _on_client_health_changed(value: float) -> void:
	if not has_node("ProgressBar"):
		return
	$ProgressBar.value = value
	# Only hide health bar when actually dead (health <= 0 AND max_value is set)
	var health_max: float = ability_system_component.get_attribute_value(Stat.HEALTH_MAX)
	if value <= 0.0 and health_max > 0.0:
		$ProgressBar.visible = false
	elif health_max > 0.0:
		$ProgressBar.visible = true


func _on_client_health_max_changed(value: float) -> void:
	if not has_node("ProgressBar"):
		return
	$ProgressBar.max_value = value


func _update_health_bar_from_sync() -> void:
	# Initialize health bar with current synced values
	# This ensures the health bar displays correctly on first load
	if not has_node("ProgressBar"):
		return
	
	var health: float = ability_system_component.get_attribute_value(Stat.HEALTH)
	var health_max: float = ability_system_component.get_attribute_value(Stat.HEALTH_MAX)
	
	# Ensure max_value is set (important for initial display)
	if health_max > 0.0:
		$ProgressBar.max_value = health_max
	
	$ProgressBar.value = health
	
	# Always show health bar if max_value is set (entity is initialized)
	if health_max > 0.0:
		$ProgressBar.visible = true
		if health <= 0.0:
			$ProgressBar.visible = false
	


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
			# Don't change animation if dead
			if is_dead:
				return
			locomotion_state_machine.travel(&"locomotion_idle")
		Animations.RUN:
			# Don't change animation if dead
			if is_dead:
				return
			locomotion_state_machine.travel(&"locomotion_run")
		Animations.DEATH:
			# Play death animation directly from locomotion library
			# Death is a one-shot animation that hides hands and plays death sprite animation
			if not multiplayer.is_server():
				# Stop locomotion state machine to prevent it from reverting to idle
				animation_tree.active = false
				animation_player.play(&"locomotion/death")
				# Connect to animation finished to keep death animation on last frame
				if not animation_player.animation_finished.is_connected(_on_death_animation_finished):
					animation_player.animation_finished.connect(_on_death_animation_finished)
	anim = new_anim


func _set_flip(new_flip: bool) -> void:
	animated_sprite.flip_h = new_flip
	hand_offset.scale.x = -1 if new_flip else 1
	flipped = new_flip


func _set_pivot(new_pivot: float) -> void:
	pivot = new_pivot
	hand_pivot.rotation = new_pivot


func _on_death_animation_finished(anim_name: StringName) -> void:
	# When death animation finishes, keep it on the last frame
	if anim_name == &"locomotion/death" and is_dead:
		# The locomotion/death animation already called AnimatedSprite2D.play("death")
		# Wait for the death sprite animation to finish, then stop on last frame
		if animated_sprite:
			# Connect to animated_sprite's animation_finished if not already connected
			if not animated_sprite.animation_finished.is_connected(_on_death_sprite_animation_finished):
				animated_sprite.animation_finished.connect(_on_death_sprite_animation_finished)


func _on_death_sprite_animation_finished() -> void:
	# When death sprite animation finishes, keep it on the last frame
	if is_dead and animated_sprite and animated_sprite.animation == &"death":
		animated_sprite.stop()
		# Set to last frame of death animation
		if animated_sprite.sprite_frames:
			var last_frame: int = animated_sprite.sprite_frames.get_frame_count(&"death") - 1
			if last_frame >= 0:
				animated_sprite.frame = last_frame


func _on_health_changed(new_health: float) -> void:
	if not multiplayer.is_server():
		return
	
	# Check for death - only if health_max is set (indicating initialization is complete)
	# This prevents false positives during initialization when health might be 0.0
	var health_max: float = ability_system_component.get_attribute_value(Stat.HEALTH_MAX)
	if new_health <= 0.0 and health_max > 0.0 and not is_dead:
		is_dead = true
		anim = Animations.DEATH
		# Don't disable physics_process - let it run but return early if dead
		# This allows NPCs to still process death logic if needed
		# Disable collision for movement
		if has_node("CollisionShape2D"):
			$CollisionShape2D.set_deferred("disabled", true)
		# Keep HurtBox enabled so dead entities can still be hit (for potential respawn logic)
		# But we could disable it if we want dead entities to be invulnerable
