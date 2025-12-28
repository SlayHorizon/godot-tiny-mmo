class_name Mob
extends Character


signal display_name_changed(new_name: String)

@export var mob_resource: MobResource

var behavior: Callable = hostile_behavior
var arr: Array[Player]

var display_name: String = "Mob":
	set = _set_display_name

var container: ReplicatedPropsContainer
var prop_id: int
var timer: float
var cooldown: float = 0.7
var is_charging: bool = false
var charge_start_time: float = 0.0
var charge_direction: Vector2 = Vector2.ZERO

# Track spawn position for respawn
var spawn_position: Vector2

@onready var detection_area: Area2D = $DetectionArea


func _ready() -> void:
	# Call parent _ready() first to set up base character functionality
	super._ready()
	
	# Store spawn position for respawn
	spawn_position = global_position
	
	# Initialize display name (triggers signal for label update on client)
	if not multiplayer.is_server():
		display_name_changed.emit(display_name)
		set_physics_process(false)
		return
	
	# Validate mob_resource exists
	if not mob_resource:
		push_error("Mob has no mob_resource assigned! Please assign a MobResource in the Inspector.")
		return
	
	# Connect detection area signals (one-time connections)
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	# Setup container and spawn - match NPC pattern
	var setup_and_spawn_func: Callable = func():
		# If container and prop_id are already set (e.g., by respawn manager), use those
		if not container or prop_id < 0:
			# Try to get container from parent (for scene-placed mobs)
			container = get_parent() as ReplicatedPropsContainer
			if not container:
				push_error("Mob must be a direct child of ReplicatedPropsContainer! Current parent: %s" % get_parent().name)
				return
			
			# Get prop_id from container (assumes container is baked)
			prop_id = container.child_id_of_node(self)
			if prop_id < 0:
				push_error("Mob '%s': Container '%s' is not baked! Please select the container and click the 'Bake' button in the Inspector, then save the scene." % [name, container.name])
				return
		
		# Spawn the mob (initializes everything)
		spawn()
	
	# Check if parent is already ready, otherwise wait for it
	var parent: Node = get_parent()
	if not parent:
		push_error("Mob has no parent!")
		return
	
	if parent.is_node_ready():
		# Parent already ready, call immediately
		setup_and_spawn_func.call()
	else:
		# Wait for parent to be ready
		parent.ready.connect(setup_and_spawn_func)


## Spawn/initialize the mob from its resource
## This method handles all initialization and can be called from _ready() or respawn
## For object pooling: fully resets state when reusing a mob instance
func spawn() -> void:
	if not multiplayer.is_server():
		return
	
	if not mob_resource:
		push_error("Mob.spawn(): mob_resource is not set!")
		return
	
	if not container or prop_id < 0:
		push_error("Mob.spawn(): container and prop_id must be set before calling spawn()!")
		return
	
	# Reset state to alive
	is_dead = false
	
	# Reset AI state
	arr.clear()
	is_charging = false
	timer = 0.0
	
	# Reset animation to IDLE (from DEATH if respawning)
	# Re-enable animation tree if it was disabled during death
	if not multiplayer.is_server():
		if animation_tree:
			animation_tree.active = true
		# Stop any playing death animations and reset sprite
		if animated_sprite:
			animated_sprite.stop()
			animated_sprite.frame = 0
		if animation_player:
			animation_player.stop()
	# Set anim to IDLE (this will trigger _set_anim which handles animation tree)
	anim = Character.Animations.IDLE
	# Sync anim to clients
	if container and prop_id >= 0:
		container.queue_op(prop_id, "rp_set_anim", [Character.Animations.IDLE as int])
	
	# Reset position to spawn position (may have variance from original)
	global_position = spawn_position
	
	# Re-enable visibility and processing (was disabled on death for object pooling)
	visible = true
	set_process(true)
	set_physics_process(true)
	
	# Re-enable collision shape (was disabled on death)
	if has_node("CollisionShape2D"):
		var collision_shape: CollisionShape2D = get_node("CollisionShape2D")
		if collision_shape:
			collision_shape.disabled = false
	
	# Ensure HurtBox is monitorable (so it can be hit by projectiles)
	if has_node("HurtBox"):
		var hurtbox: Area2D = get_node("HurtBox")
		if hurtbox:
			hurtbox.monitorable = true
			hurtbox.monitoring = false  # HurtBox doesn't need to monitor, just be monitorable
			if hurtbox.collision_layer == 0:
				hurtbox.collision_layer = 1
	
	# Initialize health and stats BEFORE connecting watchers
	# This prevents the watcher from being called with 0.0 and triggering death
	var asc: AbilitySystemComponent = ability_system_component
	
	# Set health from resource (or defaults if not in base_stats)
	var health_max: float = mob_resource.base_stats.get(Stat.HEALTH_MAX, 100.0)
	var health: float = mob_resource.base_stats.get(Stat.HEALTH, health_max)
	asc.set_attribute_value(Stat.HEALTH_MAX, health_max)
	asc.set_attribute_value(Stat.HEALTH, health)
	
	# Initialize all other stats from resource
	initialize_from_resource(mob_resource)
	
	# Connect to death signal AFTER health is initialized (only if not already connected)
	if not asc.entity_died.is_connected(_on_mob_died):
		asc.entity_died.connect(_on_mob_died)
	
	# Also ensure InstanceServer's XP award handler is connected
	# Find ServerInstance by traversing up the tree
	var current: Node = get_parent()
	while current:
		if current is ServerInstance:
			var instance: ServerInstance = current as ServerInstance
			# Connect to instance's _on_entity_died if not already connected
			if not asc.entity_died.is_connected(instance._on_entity_died):
				asc.entity_died.connect(instance._on_entity_died)
			break
		current = current.get_parent()
	
	# Sync skin_id and display_name through container using rp_ methods
	container.set_baseline_ops(prop_id, [
		["rp_set_skin_id", [mob_resource.sprite_id]],
		["rp_set_display_name", [mob_resource.display_name]]
	])
	container.queue_op(prop_id, "rp_set_skin_id", [mob_resource.sprite_id])
	container.queue_op(prop_id, "rp_set_display_name", [mob_resource.display_name])
	
	# Also set locally on server
	rp_set_skin_id(mob_resource.sprite_id)
	rp_set_display_name(mob_resource.display_name)
	
	# Equip weapon if specified
	if mob_resource.weapon_slug != "":
		container.set_baseline_ops(prop_id, [["rp_equip", [mob_resource.weapon_slug]]])
		container.queue_op(prop_id, "rp_equip", [mob_resource.weapon_slug])
		rp_equip(mob_resource.weapon_slug)
	
	# Ensure detection area is enabled and check for existing bodies
	if detection_area:
		detection_area.monitoring = true
		
		# Check for players already in the detection area (they won't trigger body_entered)
		var overlapping_bodies: Array = detection_area.get_overlapping_bodies()
		for body in overlapping_bodies:
			if body is Player:
				arr.append(body)
	
	# Ensure physics process is enabled
	set_physics_process(true)


func initialize_from_resource(resource: MobResource) -> void:
	mob_resource = resource
	
	# Set display name
	display_name = resource.display_name
	
	# Set sprite/animations via skin_id
	skin_id = resource.sprite_id
	
	# Set attack cooldown
	cooldown = resource.attack_cooldown
	
	# Set detection area radius
	if detection_area:
		if detection_area.has_node("CollisionShape2D"):
			var shape: CircleShape2D = detection_area.get_node("CollisionShape2D").shape as CircleShape2D
			if shape:
				shape.radius = resource.detection_radius
	
	# Initialize stats from base_stats (health is set separately in spawn() to avoid triggering death)
	var asc: AbilitySystemComponent = ability_system_component
	for stat_name: StringName in resource.base_stats:
		# Skip health and health_max - these are set in spawn() before connecting watchers
		if stat_name == Stat.HEALTH or stat_name == Stat.HEALTH_MAX:
			continue
		var value: float = resource.base_stats[stat_name]
		asc.set_attribute_value(stat_name, value)
	
	# Initialize mana if defined
	if resource.mana_max > 0.0:
		asc.set_attribute_value(Stat.MANA_MAX, resource.mana_max)
		asc.set_attribute_value(Stat.MANA, resource.mana_max)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	
	# Don't process if dead
	if is_dead:
		return
	
	if is_charging:
		# Safety check: don't release arrows if dead
		if is_dead:
			is_charging = false
			charge_direction = Vector2.ZERO
			return
		
		# Check if weapon is equipped
		if not equipment_component._mounted.has(&"weapon"):
			is_charging = false
			return
		
		var now: float = Time.get_ticks_msec() / 1000.0
		var weapon: Weapon = equipment_component._mounted.get(&"weapon", null)
		var charge_time: float = 0.4  # Default charge time
		if weapon and "charge_time_s" in weapon:
			charge_time = weapon.charge_time_s
		
		if now - charge_start_time >= charge_time:
			# Double-check we're not dead before releasing arrow
			if is_dead:
				is_charging = false
				charge_direction = Vector2.ZERO
				return
			# Release the arrow
			if equipment_component.can_use(&"weapon", 1):
				equipment_component._mounted[&"weapon"].perform_action(1, charge_direction)
				if container:
					container.queue_op(prop_id, "rp_attack_release", [charge_direction])
			is_charging = false
		return
	
	timer += delta
	if timer >= cooldown and arr and arr.size() > 0:
		# Check if weapon is equipped
		if not equipment_component._mounted.has(&"weapon"):
			return
		
		timer = 0
		if equipment_component.can_use(&"weapon", 0):
			var dir: Vector2 = global_position.direction_to(arr.front().global_position)
			equipment_component._mounted[&"weapon"].perform_action(0, dir)
			if container:
				container.queue_op(prop_id, "rp_attack", [dir])
			# Start charging
			is_charging = true
			charge_start_time = Time.get_ticks_msec() / 1000.0
			charge_direction = dir


func rp_equip(weapon_slug: String):
	var weapon_item: WeaponItem = ContentRegistryHub.load_by_slug(&"items", weapon_slug) as WeaponItem
	if not weapon_item:
		push_error("Mob.rp_equip: Failed to load weapon: %s" % weapon_slug)
		return
	var weapon: WeaponItem = weapon_item.duplicate(true)
	equipment_component.equip(weapon.slot.key, weapon)


func rp_attack(dir: Vector2):
	if not equipment_component._mounted.has(&"weapon"):
		push_warning("Mob.rp_attack: No weapon equipped!")
		return
	equipment_component._mounted[&"weapon"].perform_action(0, dir)


func rp_attack_release(dir: Vector2):
	if not equipment_component._mounted.has(&"weapon"):
		push_warning("Mob.rp_attack_release: No weapon equipped!")
		return
	equipment_component._mounted[&"weapon"].perform_action(1, dir)


func rp_set_skin_id(id: int) -> void:
	skin_id = id


func rp_set_display_name(new_display_name: String) -> void:
	display_name = new_display_name


func rp_set_anim(anim_value: int) -> void:
	# Convert int to Animations enum
	var new_anim: Character.Animations = anim_value as Character.Animations
	# If respawning (setting to IDLE), ensure animation tree is active
	if new_anim == Character.Animations.IDLE and not multiplayer.is_server():
		if animation_tree:
			animation_tree.active = true
		# Stop any death animations
		if animated_sprite:
			animated_sprite.stop()
		if animation_player:
			animation_player.stop()
	anim = new_anim


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body is Player:
		arr.append(body)


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body is Player:
		arr.erase(body)


func hostile_behavior(player: Player) -> void:
	pass


func _set_display_name(new_name: String) -> void:
	display_name = new_name
	if not multiplayer.is_server():
		display_name_changed.emit(new_name)


## Override to sync anim variable to clients when death occurs
func _on_health_changed(new_health: float) -> void:
	# Call parent to handle death logic (sets anim = DEATH)
	super._on_health_changed(new_health)
	
	# Sync anim to clients via ReplicatedPropsContainer (server-side only)
	if multiplayer.is_server() and container and prop_id >= 0 and is_dead:
		# Sync the DEATH animation to clients
		container.queue_op(prop_id, "rp_set_anim", [Character.Animations.DEATH as int])


func _on_mob_died(entity: Character, killer: Character) -> void:
	# Stop AI behavior immediately
	arr.clear()
	is_charging = false
	timer = 0.0
	# Cancel any in-flight attacks by clearing charge state
	charge_direction = Vector2.ZERO
	charge_start_time = 0.0
	
	# Hide and disable the mob instead of freeing it (object pooling)
	visible = false
	set_process(false)
	set_physics_process(false)
	
	# Disable collision and detection (use set_deferred to avoid physics errors during query flush)
	if has_node("CollisionShape2D"):
		var collision_shape: CollisionShape2D = get_node("CollisionShape2D")
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
	
	if detection_area:
		detection_area.set_deferred("monitoring", false)
	
	# Disable HurtBox (so it can't be hit while dead)
	# Must use set_deferred to avoid physics errors during query flush
	if has_node("HurtBox"):
		var hurtbox: Area2D = get_node("HurtBox")
		if hurtbox:
			hurtbox.set_deferred("monitorable", false)
			hurtbox.set_deferred("monitoring", false)
	
	# Award XP and gold to killer (if it's a player)
	if killer is Player and killer.player_resource:
		var player: Player = killer as Player
		# Award experience
		if mob_resource and mob_resource.experience_reward > 0:
			# TODO: Integrate with XP system when available
			pass
		# Award gold
		if mob_resource and mob_resource.gold_reward > 0:
			# TODO: Integrate with gold system when available
			pass
	
	# Register death with respawn manager
	# Find ServerInstance by traversing up the tree
	var current: Node = get_parent()
	var found_instance: bool = false
	while current:
		if current is ServerInstance:
			var instance: ServerInstance = current as ServerInstance
			if instance.has_node("MobRespawnManager"):
				var respawn_manager: MobRespawnManager = instance.get_node("MobRespawnManager")
				respawn_manager.register_mob_death(self)
				found_instance = true
			break
		current = current.get_parent()
	
	if not found_instance:
		push_error("Mob._on_mob_died: Could not find ServerInstance with MobRespawnManager!")
