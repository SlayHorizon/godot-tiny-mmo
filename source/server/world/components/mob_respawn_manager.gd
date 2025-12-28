class_name MobRespawnManager
extends Node


const RESPAWN_CHECK_INTERVAL: float = 1.0
const MAX_SPAWN_ATTEMPTS: int = 10  # Maximum attempts to find a valid spawn position


var dead_mobs: Dictionary = {}  # unique_id -> respawn_data
var _next_unique_id: int = 0
var check_timer: float = 0.0

var instance: ServerInstance


func _ready() -> void:
	instance = get_parent() as ServerInstance
	if not instance:
		push_error("MobRespawnManager must be a child of ServerInstance!")
	set_process(true)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	
	check_timer += delta
	if check_timer >= RESPAWN_CHECK_INTERVAL:
		check_timer = 0.0
		_check_and_respawn_mobs()


func register_mob_death(mob: Mob) -> void:
	if not mob or not mob.mob_resource:
		push_error("MobRespawnManager.register_mob_death: Invalid mob or missing mob_resource")
		return
	
	# Store respawn data, including parent path for subgroups
	var parent_node: Node = mob.get_parent()
	var parent_path: NodePath = NodePath()
	if parent_node and parent_node != mob.container:
		# Mob is in a subgroup, store the path from container to parent
		parent_path = mob.container.get_path_to(parent_node)
	
	# Check if we already have respawn_data for this mob (from previous death)
	# If so, preserve the original_spawn_position to prevent drift
	var unique_id: int = mob.prop_id
	var existing_data: Dictionary = dead_mobs.get(unique_id, {})
	var original_spawn_position: Vector2 = existing_data.get("original_spawn_position", mob.spawn_position)
	
	var respawn_data: Dictionary = {
		"mob": mob,  # Store mob reference for object pooling (reuse same instance)
		"spawn_position": mob.spawn_position,  # Current spawn position (may have variance)
		"original_spawn_position": original_spawn_position,  # Original spawn position (base for variance)
		"death_time": Time.get_ticks_msec() / 1000.0,
		"respawn_delay": mob.mob_resource.respawn_delay,
		"mob_resource": mob.mob_resource,
		"container": mob.container,
		"prop_id": mob.prop_id,
		"parent_path": parent_path  # Path from container to parent subgroup (empty if direct child)
	}
	
	# Use prop_id as key for object pooling (one mob per prop_id)
	# This allows us to track and reuse the same mob instance
	dead_mobs[unique_id] = respawn_data
	
	# Don't free the mob - it's hidden/disabled and will be reused
	# The mob is already hidden and disabled in _on_mob_died()


func _check_and_respawn_mobs() -> void:
	var to_respawn: Array = []  # Array of [unique_id, respawn_data]
	var to_remove: Array = []  # Array of unique_ids to remove (invalid mobs)
	var now: float = Time.get_ticks_msec() / 1000.0
	
	for unique_id in dead_mobs.keys():
		var respawn_data: Dictionary = dead_mobs[unique_id]
		var mob_resource: MobResource = respawn_data.get("mob_resource", null)
		var mob: Mob = respawn_data.get("mob", null)
		
		# Check if mob resource is missing
		if not mob_resource:
			to_remove.append(unique_id)
			continue
		
		# Check if mob instance is still valid (object pooling - mob should still exist)
		if not mob or not is_instance_valid(mob):
			to_remove.append(unique_id)
			continue
		
		# Calculate time until respawn
		var death_time: float = respawn_data.get("death_time", 0.0)
		var respawn_delay: float = respawn_data.get("respawn_delay", 30.0)
		
		if can_respawn(respawn_data, now):
			to_respawn.append([unique_id, respawn_data])
	
	# Remove invalid entries
	for unique_id in to_remove:
		dead_mobs.erase(unique_id)
	
	# Respawn eligible mobs
	for entry: Array in to_respawn:
		var unique_id: int = entry[0]
		var respawn_data: Dictionary = entry[1]
		respawn_mob(respawn_data)
		dead_mobs.erase(unique_id)


func can_respawn(respawn_data: Dictionary, current_time: float) -> bool:
	var death_time: float = respawn_data.get("death_time", 0.0)
	var respawn_delay: float = respawn_data.get("respawn_delay", 30.0)
	var spawn_position: Vector2 = respawn_data.get("spawn_position", Vector2.ZERO)
	var mob_resource: MobResource = respawn_data.get("mob_resource", null)
	
	if not mob_resource:
		return false
	
	# Check if enough time has passed
	if current_time - death_time < respawn_delay:
		return false
	
	# Check if any players are nearby
	var check_radius: float = mob_resource.get_respawn_check_radius()
	
	if _has_players_nearby(spawn_position, check_radius):
		return false
	
	return true


func _has_players_nearby(position: Vector2, radius: float) -> bool:
	if not instance:
		return false
	
	# Check all players in the instance
	for peer_id: int in instance.connected_peers:
		var player: Player = instance.players_by_peer_id.get(peer_id, null)
		if not player or not is_instance_valid(player):
			continue
		
		var distance: float = position.distance_to(player.global_position)
		if distance <= radius:
			return true
	
	return false


func respawn_mob(respawn_data: Dictionary) -> void:
	var mob: Mob = respawn_data.get("mob", null)
	var mob_resource: MobResource = respawn_data.get("mob_resource", null)
	var spawn_position: Vector2 = respawn_data.get("spawn_position", Vector2.ZERO)
	var container: ReplicatedPropsContainer = respawn_data.get("container", null)
	var original_prop_id: int = respawn_data.get("prop_id", -1)
	
	if not mob_resource or not container or original_prop_id < 0:
		push_error("MobRespawnManager.respawn_mob: Invalid respawn_data or missing prop_id")
		return
	
	# Verify mob instance is still valid (object pooling - reuse existing instance)
	if not mob or not is_instance_valid(mob):
		push_error("MobRespawnManager.respawn_mob: Mob instance is invalid or was freed! Cannot reuse.")
		return
	
	# Verify container still exists
	if not is_instance_valid(container):
		push_error("MobRespawnManager.respawn_mob: Container is invalid! Cannot respawn mob.")
		return
	
	# Calculate respawn position with variance (random offset within radius from original spawn)
	# Use original_spawn_position if available (to prevent drift), otherwise use spawn_position
	var original_spawn: Vector2 = respawn_data.get("original_spawn_position", spawn_position)
	var respawn_position: Vector2 = original_spawn
	
	if mob_resource.respawn_position_variance > 0.0:
		# Try to find a valid spawn position within the variance radius
		respawn_position = _find_valid_spawn_position(mob, original_spawn, mob_resource.respawn_position_variance)
		if respawn_position == Vector2.ZERO:
			# Fallback to original spawn if no valid position found
			respawn_position = original_spawn
	
	# Ensure mob is still in the scene tree and has correct container/prop_id
	# (It should be, since we didn't free it)
	if not mob.is_inside_tree():
		push_error("MobRespawnManager.respawn_mob: Mob is not in scene tree! This shouldn't happen with object pooling.")
		return
	
	# Verify container and prop_id are still set (they should be)
	if mob.container != container or mob.prop_id != original_prop_id:
		push_warning("MobRespawnManager.respawn_mob: Mob container/prop_id mismatch, updating...")
		mob.container = container
		mob.prop_id = original_prop_id
	
	# Ensure container's id_to_node mapping is correct (pointing to our reused mob)
	container.id_to_node[original_prop_id] = mob
	container.node_to_id[mob] = original_prop_id
	
	# Update mob's spawn_position to the varied respawn position
	# This will be used by spawn() to set the mob's global_position
	mob.spawn_position = respawn_position
	
	# Call spawn() directly - mob is already in tree, no need for call_deferred
	# spawn() will reset all state, re-enable the mob, and sync to clients
	mob.spawn()
	
	# No need to queue_spawn - clients already know about this prop_id
	# Just queue the ops to update appearance/weapon for the respawned mob
	var baseline_ops: Array = []
	if mob_resource.weapon_slug != "":
		baseline_ops.append(["rp_equip", [mob_resource.weapon_slug]])
	baseline_ops.append(["rp_set_skin_id", [mob_resource.sprite_id]])
	baseline_ops.append(["rp_set_display_name", [mob_resource.display_name]])
	container.set_baseline_ops(original_prop_id, baseline_ops)
	
	# Queue ops for existing clients (they'll see the mob "respawn" with updated state)
	if mob_resource.weapon_slug != "":
		container.queue_op(original_prop_id, "rp_equip", [mob_resource.weapon_slug])
	container.queue_op(original_prop_id, "rp_set_skin_id", [mob_resource.sprite_id])
	container.queue_op(original_prop_id, "rp_set_display_name", [mob_resource.display_name])


## Check if a position is valid for spawning (no collisions with static objects)
func _is_position_valid(mob: Mob, position: Vector2) -> bool:
	if not mob or not is_instance_valid(mob):
		return false
	
	# Get the mob's collision shape to use for checking
	var collision_shape: CollisionShape2D = null
	if mob.has_node("CollisionShape2D"):
		collision_shape = mob.get_node("CollisionShape2D")
	
	if not collision_shape or not collision_shape.shape:
		# No collision shape to check, assume position is valid
		return true
	
	# Get the physics space from the mob's world
	var space_state: PhysicsDirectSpaceState2D = mob.get_world_2d().direct_space_state
	
	# Create a query to check for collisions at this position
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = 0xFFFFFFFF  # Check all collision layers
	query.exclude = [mob]  # Exclude the mob itself from the query
	
	# Check for collisions
	var results: Array = space_state.intersect_shape(query, 1)
	
	# Position is valid if no collisions found
	return results.is_empty()


## Find a valid spawn position within the variance radius
## Tries multiple random positions and returns the first valid one
func _find_valid_spawn_position(mob: Mob, center: Vector2, radius: float) -> Vector2:
	if not mob or not is_instance_valid(mob):
		return Vector2.ZERO
	
	# Try multiple random positions
	for attempt in range(MAX_SPAWN_ATTEMPTS):
		var angle: float = randf() * TAU  # Random angle in radians
		var distance: float = randf() * radius  # Random distance within radius
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
		var test_position: Vector2 = center + offset
		
		if _is_position_valid(mob, test_position):
			return test_position
	
	# If no valid position found after all attempts, return zero to indicate failure
	return Vector2.ZERO

