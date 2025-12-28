class_name ServerInstance
extends SubViewport


signal player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper)

const PLAYER: PackedScene = preload("res://source/common/gameplay/characters/player/player.tscn")

static var world_server: WorldServer

static var global_chat_commands: Dictionary[String, ChatCommand]
static var global_role_definitions: Dictionary[String, Dictionary] = preload("res://source/server/world/data/server_roles.tres").get_roles()

var local_chat_commands: Dictionary[String, ChatCommand]
var local_role_definitions: Dictionary[String, Dictionary]
var local_role_assignments: Dictionary[int, PackedStringArray]

var players_by_peer_id: Dictionary[int, Player]
## Current connected peers to the instance.
var connected_peers: PackedInt64Array = PackedInt64Array()
## Peers coming from another instance.
var awaiting_peers: Dictionary = {}#[int, Player]

var last_accessed_time: float

var instance_map: Map
var instance_resource: InstanceResource

var synchronizer_manager: StateSynchronizerManagerServer


func _ready() -> void:
	world_server.multiplayer_api.peer_disconnected.connect(
		func(peer_id: int):
			if connected_peers.has(peer_id):
				despawn_player(peer_id)
	)
	
	synchronizer_manager = StateSynchronizerManagerServer.new()
	synchronizer_manager.name = "StateSynchronizerManager"
	synchronizer_manager.init_zones_from_map(instance_map)
	
	add_child(synchronizer_manager, true)
	
	# Add mob respawn manager
	var respawn_manager: MobRespawnManager = MobRespawnManager.new()
	respawn_manager.name = "MobRespawnManager"
	add_child(respawn_manager, true)


func load_map(map_path: String) -> void:
	if instance_map:
		instance_map.queue_free()
	instance_map = load(map_path).instantiate()
	add_child(instance_map)
	#add_child(CameraProbe.new())
	
	ready.connect(func():
		# Register all ReplicatedPropsContainers with unique IDs
		# Main container gets ID 1_000_000, others get sequential IDs
		var container_id: int = 1_000_000
		if instance_map.replicated_props_container:
			synchronizer_manager.add_container(container_id, instance_map.replicated_props_container)
			container_id += 1
		
		# Find and register all other ReplicatedPropsContainers in the scene
		_register_containers_recursive(instance_map, container_id)
		
		for child in instance_map.get_children():
			if child is InteractionArea:
				child.player_entered_interaction_area.connect(self._on_player_entered_interaction_area)
		
		# Setup entity death listeners for XP awards
		_setup_entity_death_listeners()
		)


func _register_containers_recursive(node: Node, start_id: int) -> int:
	# Recursively find and register all ReplicatedPropsContainers
	var current_id: int = start_id
	for child in node.get_children():
		if child is ReplicatedPropsContainer:
			# Skip the main container (already registered)
			if child != instance_map.replicated_props_container:
				synchronizer_manager.add_container(current_id, child)
				print_debug("InstanceServer: Registered container '%s' with ID %d" % [child.name, current_id])
				current_id += 1
		# Recursively check children
		current_id = _register_containers_recursive(child, current_id)
	return current_id


func _setup_entity_death_listeners() -> void:
	# Connect to all existing entities' death signals
	_setup_entity_death_listeners_recursive(instance_map)
	
	# Also connect to mob respawn manager to hook new mobs when they respawn
	var respawn_manager: MobRespawnManager = get_node_or_null("MobRespawnManager")
	if respawn_manager:
		# We'll connect to mob spawns via a signal or check periodically
		# For now, the recursive check should catch most cases
		pass


func _setup_entity_death_listeners_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Character:
			var character: Character = child as Character
			var asc: AbilitySystemComponent = character.ability_system_component
			if asc and not asc.entity_died.is_connected(_on_entity_died):
				asc.entity_died.connect(_on_entity_died)
		# Recursively check children
		_setup_entity_death_listeners_recursive(child)


func _on_entity_died(entity: Character, killer: Character) -> void:
	# Only award XP if killer is a Player
	if not killer is Player:
		return
	
	var player: Player = killer as Player
	if not player or not player.player_resource:
		return
	
	# Get XP reward from entity
	var xp_reward: int = 0
	
	if entity is Mob and entity.mob_resource:
		xp_reward = entity.mob_resource.experience_reward
	elif entity.has_method("get") and entity.get("npc_resource"):
		var npc_resource = entity.get("npc_resource")
		if npc_resource and npc_resource.has("experience_reward"):
			xp_reward = npc_resource.experience_reward
	
	if xp_reward <= 0:
		return
	
	# Award XP to player
	var player_resource: PlayerResource = player.player_resource
	var leveled_up: bool = player_resource.add_experience(xp_reward)
	
	# Find peer_id from players_by_peer_id
	var player_peer_id: int = -1
	for pid: int in players_by_peer_id:
		if players_by_peer_id[pid] == player:
			player_peer_id = pid
			break
	
	if player_peer_id < 0:
		return
	
	# If leveled up, update stats with scaled values
	if leveled_up:
		var scaled_stats: Dictionary[StringName, float] = player_resource.get_scaled_stats()
		var asc: AbilitySystemComponent = player.ability_system_component
		
		# Update all stats
		for stat_name: StringName in scaled_stats:
			var value: float = scaled_stats[stat_name]
			asc.set_attribute_value(stat_name, value)
		
		# Ensure health doesn't exceed new max
		var current_health: float = asc.get_attribute_value(Stat.HEALTH)
		var new_health_max: float = scaled_stats[Stat.HEALTH_MAX]
		if current_health > new_health_max:
			asc.set_attribute_value(Stat.HEALTH, new_health_max)
		
		# Sync updated stats to client
		DataSynchronizerServer._self.data_push.rpc_id(
			player_peer_id,
			&"stats.get",
			scaled_stats
		)
	
	# Always sync XP update to client (whether leveled up or not)
	var xp_required: int = XPCalculator.get_xp_required_for_level(player_resource.level + 1)
	
	var xp_data: Dictionary = {
		"experience": player_resource.experience,
		"level": player_resource.level,
		"xp_required": xp_required,
		"total_experience": player_resource.total_experience
	}
	
	DataSynchronizerServer._self.data_push.rpc_id(
		player_peer_id,
		&"xp.update",
		xp_data
	)


func _on_player_entered_interaction_area(player: Player, interaction_area: InteractionArea) -> void:
	if player.has_recently_teleported():
		return
	if interaction_area is Warper:
		player_entered_warper.emit.call_deferred(player, self, interaction_area)
	if interaction_area is Teleporter:
		player.mark_just_teleported()
		player.state_synchronizer.set_by_path(^":position", interaction_area.target.global_position)


@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	spawn_player(peer_id)


#region spawn/despawn
@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(peer_id: int) -> void:
	var player: Player
	var spawn_index: int = 0
	
	if awaiting_peers.has(peer_id):
		player = awaiting_peers[peer_id]["player"]
		spawn_index = awaiting_peers[peer_id]["target_id"]
		awaiting_peers.erase(peer_id)
	else:
		player = instantiate_player(peer_id)
		DataSynchronizerServer._self.data_push.rpc_id(peer_id, &"chat.message", {"text": get_motd(), "id": 1, "name": "Server"})
	
	player.mark_just_teleported()
	
	instance_map.add_child(player, true)
	
	players_by_peer_id[peer_id] = player
	
	#NEW
	var syn: StateSynchronizer = player.state_synchronizer
	syn.set_by_path(^":position", instance_map.get_spawn_position(spawn_index))

	print_debug("baseline server pairs:", syn.capture_baseline())
	
	# Register in sync manager AFTER we seeded states.
	synchronizer_manager.add_entity(peer_id, syn)
	synchronizer_manager.register_peer(peer_id)

	connected_peers.append(peer_id)
	_propagate_spawn(peer_id)


func instantiate_player(peer_id: int) -> Player:
	var player_resource: PlayerResource = world_server.connected_players[peer_id]
	
	var new_player: Player = PLAYER.instantiate() as Player
	new_player.name = str(peer_id)
	new_player.player_resource = player_resource
	
	var setup_new_player: Callable = func():
		var syn: StateSynchronizer = new_player.state_synchronizer
		syn.set_by_path(^":skin_id", new_player.player_resource.skin_id)
		syn.set_by_path(^":display_name", new_player.player_resource.display_name)
		
		# Initialize XP/level if new player
		if player_resource.total_experience == 0 and player_resource.level == 0:
			player_resource.level = 1
			player_resource.experience = 0
			player_resource.total_experience = 0
		elif player_resource.total_experience > 0:
			# Recalculate level from total_experience
			player_resource.level = XPCalculator.get_level_from_total_xp(player_resource.total_experience)
			# Calculate current level's XP
			var total_xp_for_current_level: int = XPCalculator.get_total_xp_for_level(player_resource.level)
			player_resource.experience = player_resource.total_experience - total_xp_for_current_level

		var asc: AbilitySystemComponent = new_player.ability_system_component
		
		# Use scaled stats based on level
		var player_stats: Dictionary[StringName, float] = player_resource.get_scaled_stats()
		const AttributesMap = preload("res://source/common/gameplay/combat/attributes/attributes_map.gd")
		var stats_from_attributes: Dictionary[StringName, float]
		stats_from_attributes.assign(AttributesMap.attr_to_stats(player_resource.attributes))
		
		# Add base player attributes to general base stats.
		for stat_name: StringName in stats_from_attributes:
			if player_stats.has(stat_name):
				player_stats[stat_name] = stats_from_attributes[stat_name]
			else:
				player_stats[stat_name] += stats_from_attributes[stat_name]
		
		player_resource.stats = player_stats
		DataSynchronizerServer._self.data_push.rpc_id(peer_id, &"stats.get", player_stats)
		
		for stat_name: StringName in player_stats:
			var value: float = player_stats[stat_name]
			print(stat_name, " : ", value)
			asc.set_attribute_value(stat_name, value)
		
		# Sync XP data to client
		var xp_required: int = XPCalculator.get_xp_required_for_level(player_resource.level + 1)
		DataSynchronizerServer._self.data_push.rpc_id(
			peer_id,
			&"xp.update",
			{
				"experience": player_resource.experience,
				"level": player_resource.level,
				"xp_required": xp_required,
				"total_experience": player_resource.total_experience
			}
		)

	new_player.ready.connect(setup_new_player,CONNECT_ONE_SHOT)
	return new_player


func get_motd() -> String:
	return world_server.world_manager.world_info.get("motd", "Default Welcome")


## Spawn the new player on all other client in the current instance
## and spawn all other players on the new client.
func _propagate_spawn(new_player_id: int) -> void:
	for peer_id: int in connected_peers:
		spawn_player.rpc_id(peer_id, new_player_id)
		if new_player_id != peer_id:
			spawn_player.rpc_id(new_player_id, peer_id)


@rpc("authority", "call_remote", "reliable", 0)
func despawn_player(peer_id: int, delete: bool = false) -> void:
	connected_peers.remove_at(connected_peers.find(peer_id))
	
	synchronizer_manager.remove_entity(peer_id)
	synchronizer_manager.unregister_peer(peer_id)
	
	var player: Player = players_by_peer_id[peer_id]
	if player:
		if delete:
			player.queue_free()
		else:
			instance_map.remove_child(player)
		players_by_peer_id.erase(peer_id)
	
	for id: int in connected_peers:
		despawn_player.rpc_id(id, peer_id)
#endregion


func get_player(peer_id: int) -> Player:
	var p: Player = players_by_peer_id.get(peer_id, null)
	return p


func get_player_syn(peer_id: int) -> StateSynchronizer:
	var p: Player = get_player(peer_id)
	return null if p == null else p.get_node_or_null(^"StateSynchronizer")


## Fixe une propriété arbitraire relative à la racine du Player via le Synchronizer.
## Exemple: ^":scale", ^"Sprite2D:modulate", ^"AbilitySystemComponent:health"
func set_player_path_value(peer_id: int, rel_path: NodePath, value: Variant) -> bool:
	var syn: StateSynchronizer = get_player_syn(peer_id)
	if syn == null:
		return false
	syn.set_by_path(rel_path, value)  # applique local + marque dirty
	return true


# To translate in english
## API “propre” pour les attributs (serveur = source de vérité).
## Utilise l’ASC si présent ; sinon fallback en poussant le miroir.
func set_player_attr_current(peer_id: int, attr: StringName, value: float) -> bool:
	var p: Player = get_player(peer_id)
	if p == null:
		return false

	var asc: AbilitySystemComponent = p.ability_system_component
	if asc != null and asc.has_method("set_attr_current"):
		asc.set_attr_current(attr, value)
		return true

	# Fallback (si pas encore d'API ASC dédiée) : pousser le miroir côté client.
	var np := NodePath("AbilitySystemComponent:" + String(attr))
	return set_player_path_value(peer_id, np, value)
