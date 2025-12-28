class_name InstanceClient
extends Node


const LOCAL_PLAYER: PackedScene = preload("res://source/client/local_player/local_player.tscn")
const DUMMY_PLAYER: PackedScene = preload("res://source/common/gameplay/characters/player/player.tscn")

static var current: InstanceClient
static var local_player: LocalPlayer

var players_by_peer_id: Dictionary[int, Player]

var synchronizer_manager: StateSynchronizerManagerClient
var instance_map: Map


static func _static_init() -> void:
	var _on_data_receive: Callable = func(data: Dictionary):
		if data.is_empty() or not data.has_all(["p", "d", "i"]):
			return
		var player: Player = InstanceClient.current.players_by_peer_id.get(data["p"])
		if not player:
			return
		
		# To fix
		if player.equipment_component._mounted.has(&"weapon"):
			player.equipment_component._mounted[&"weapon"].perform_action(data["i"], data["d"])

	DataSynchronizerClient.subscribe(&"action.perform", _on_data_receive)


func _ready() -> void:
	current = self
	
	synchronizer_manager = StateSynchronizerManagerClient.new()
	synchronizer_manager.name = "StateSynchronizerManager"

	# Register all ReplicatedPropsContainers with unique IDs (must match server IDs)
	var container_id: int = 1_000_000
	if instance_map.replicated_props_container:
		synchronizer_manager.add_container(container_id, instance_map.replicated_props_container)
		container_id += 1
	
	# Find and register all other ReplicatedPropsContainers in the scene
	_register_containers_recursive(instance_map, container_id)

	add_child(synchronizer_manager, true)


@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	pass


#region spawn/despawn
@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(player_id: int) -> void:
	var new_player: Player
	
	if player_id == multiplayer.get_unique_id():
		# Reuse local player if already exists.
		if local_player and is_instance_valid(local_player):
			new_player = local_player
		else:
			new_player = LOCAL_PLAYER.instantiate() as LocalPlayer
			local_player = new_player

		# Always update instance and sync manager references.
		local_player.synchronizer_manager = synchronizer_manager
	else:
		new_player = DUMMY_PLAYER.instantiate()
	
	new_player.name = str(player_id)
	
	players_by_peer_id[player_id] = new_player
	
	if not new_player.is_inside_tree():
		instance_map.add_child(new_player)
		#instance_map.add_child(new_player)
	
	var sync: StateSynchronizer = new_player.state_synchronizer
	synchronizer_manager.add_entity(player_id, sync) 


@rpc("authority", "call_remote", "reliable", 0)
func despawn_player(player_id: int) -> void:
	synchronizer_manager.remove_entity(player_id)
	
	var player: Player = players_by_peer_id.get(player_id, null)
	if player and player != local_player:
		player.queue_free()
	players_by_peer_id.erase(player_id)
#endregion


func _register_containers_recursive(node: Node, start_id: int) -> int:
	# Recursively find and register all ReplicatedPropsContainers
	var current_id: int = start_id
	for child in node.get_children():
		if child is ReplicatedPropsContainer:
			# Skip the main container (already registered)
			if child != instance_map.replicated_props_container:
				synchronizer_manager.add_container(current_id, child)
				print_debug("InstanceClient: Registered container '%s' with ID %d" % [child.name, current_id])
				current_id += 1
		# Recursively check children
		current_id = _register_containers_recursive(child, current_id)
	return current_id
