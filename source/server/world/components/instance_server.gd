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
var awaiting_peers: Dictionary[int, Dictionary] = {}#[int, Player]

var last_accessed_time: float

var instance_map: Map
var instance_resource: InstanceResource

var synchronizer_manager: StateSynchronizerManagerServer


func _ready() -> void:
	world_server.multiplayer_api.peer_disconnected.connect(
		func(peer_id: int):
			if connected_peers.has(peer_id):
				var player: Player = get_player(peer_id)
				if player:
					player.player_resource.last_position = player.global_position
				despawn_player(peer_id)
	)

	synchronizer_manager = StateSynchronizerManagerServer.new()
	synchronizer_manager.name = "StateSynchronizerManager"
	synchronizer_manager.init_zones_from_map(instance_map)
	
	add_child(synchronizer_manager, true)


func load_map(map_path: String) -> void:
	if instance_map:
		instance_map.queue_free()
	if ResourceLoader.exists(map_path):
		var map_scene: PackedScene = load(map_path)
		instance_map = map_scene.instantiate()
		add_child.call_deferred(instance_map)

	ready.connect(func():
		if instance_map.replicated_props_container:
			synchronizer_manager.add_container(1_000_000, instance_map.replicated_props_container)
		for child in instance_map.get_children():
			if child is InteractionArea:
				child.player_entered_interaction_area.connect(self._on_player_entered_interaction_area)
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
	var spawn_position: Vector2

	if awaiting_peers.has(peer_id):
		var player_info: Dictionary = awaiting_peers[peer_id]
		player = player_info["player"] if "player" in player_info else instantiate_player(peer_id)
		spawn_index = player_info.get("target_id", 0)
		spawn_position = player_info["target_position"] if "target_position" in player_info else instance_map.get_spawn_position(spawn_index)
		awaiting_peers.erase(peer_id)
	else:
		player = instantiate_player(peer_id)
		spawn_position = instance_map.get_spawn_position(spawn_index)
		WorldServer.curr.chat_service.push_system_to_player(self, player.player_resource.player_id, get_motd())
		#WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", {"text": get_motd(), "id": 1, "name": "Server"})

	player.player_resource.current_instance = instance_resource.instance_name
	player.mark_just_teleported()
	
	instance_map.add_child(player, true)
	
	players_by_peer_id[peer_id] = player
	
	if spawn_position == Vector2.ZERO:
		spawn_position = instance_map.get_spawn_position(0)

	var syn: StateSynchronizer = player.state_synchronizer
	syn.set_by_path(^":position", spawn_position)

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
		

		var asc: AbilitySystemComponent = new_player.ability_system_component
		
		var player_stats: Dictionary[StringName, float] = player_resource.BASE_STATS
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
		WorldServer.curr.data_push.rpc_id(peer_id, &"stats.get", player_stats)
		
		for stat_name: StringName in player_stats:
			var value: float = player_stats[stat_name]
			print(stat_name, " : ", value)
			asc.set_attribute_value(stat_name, value)

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
