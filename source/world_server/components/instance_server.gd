class_name ServerInstance
extends SubViewport


signal player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper)

const PLAYER = preload("res://source/common/entities/characters/player/player.tscn")

var world_server: WorldServer

var entity_collection: Dictionary = {}#[int, Entity]
## Current connected peers to the instance.
var connected_peers: PackedInt64Array = []
## Peers coming from another instance.
var awaiting_peers: Dictionary = {}#[int, Player]

var instance_map: Map
var instance_resource: InstanceResource


func _ready() -> void:
	world_server.multiplayer_api.peer_disconnected.connect(
		func(peer_id: int):
			if connected_peers.has(peer_id):
				despawn_player(peer_id)
	)


func _physics_process(_delta: float) -> void:
	var state: Dictionary = {"EC" = {}}
	for entity_id: int in entity_collection:
		state["EC"][entity_id] = (entity_collection[entity_id] as Entity).sync_state
	state["T"] = Time.get_unix_time_from_system()
	for peer_id: int in connected_peers:
		fetch_instance_state.rpc_id(peer_id, state)


func load_map(map_path: String) -> void:
	if instance_map:
		instance_map.queue_free()
	instance_map = load(map_path).instantiate()
	add_child(instance_map)
	#add_child(CameraProbe.new())
	
	for child in instance_map.get_children():
		if child is InteractionArea:
			child.player_entered_interaction_area.connect(self._on_player_entered_interaction_area)


func _on_player_entered_interaction_area(player: Player, interaction_area: InteractionArea) -> void:
	if player.just_teleported:
		return
	if interaction_area is Warper:
		interaction_area = interaction_area as Warper
		player_entered_warper.emit.call_deferred(player, self, interaction_area as Warper)
	if interaction_area is Teleporter:
		if not player.just_teleported:
			player.just_teleported = true
			update_entity(player, {"position": interaction_area.target.global_position})


@rpc("authority", "call_remote", "reliable", 1)
func update_entity(entity, to_update: Dictionary) -> void:
	for thing: String in to_update:
		entity.set_indexed(thing, to_update[thing])
	for peer_id: int in connected_peers:
		update_entity.rpc_id(peer_id, entity.name.to_int(), to_update)


@rpc("authority", "call_remote", "reliable", 0)
func fetch_instance_state(_new_state: Dictionary):
	pass


@rpc("any_peer", "call_remote", "reliable", 0)
func fetch_player_state(sync_state: Dictionary) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if entity_collection.has(peer_id):
		var entity: Entity = entity_collection[peer_id] as Entity
		if entity.sync_state["T"] < sync_state["T"]:
			# Security issue: add a white list
			#if sync_state.keys().all(func(x): return ["position", "sprite_frames", "animation", "flipped", "T"].any(func(y): return x == y)):
			for key: String in sync_state:
				entity.sync_state[key] = sync_state[key]
			entity.sync_state = entity.sync_state


@rpc("any_peer", "call_remote", "reliable", 0)
func player_trying_to_change_weapon(weapon_path: String, _side: bool = true) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	# Check if player has the weapon
	var entity: Entity = entity_collection[peer_id] as Entity
	update_entity(entity, {"weapon_name_right": weapon_path})
	entity.spawn_state["weapon_name_right"] = weapon_path
	


@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	spawn_player(peer_id)

#region spawn/despawn
@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(peer_id: int, spawn_state: Dictionary = {}) -> void:
	var player: Player
	var spawn_index: int = 0
	if awaiting_peers.has(peer_id):
		player = awaiting_peers[peer_id]["player"]
		spawn_index = awaiting_peers[peer_id]["target_id"]
		awaiting_peers.erase(peer_id)
	else:
		player = instantiate_player(peer_id)
	player.spawn_state["position"] = instance_map.get_spawn_position(spawn_index)
	player.just_teleported = true
	add_child(player, true)
	entity_collection[peer_id] = player
	connected_peers.append(peer_id)
	propagate_spawn(peer_id, player.spawn_state)


func instantiate_player(peer_id: int) -> Player:
	var new_player: Player = PLAYER.instantiate() as Player
	new_player.name = str(peer_id)
	new_player.spawn_state = {
		"character_class": world_server.player_list[peer_id][world_server.player_list[peer_id].keys()[0]]["class"],
		"display_name": world_server.player_list[peer_id][world_server.player_list[peer_id].keys()[0]]["name"]
	}
	return new_player

## Spawn the new player on all other client in the current instance
## and spawn all other players on the new client.
func propagate_spawn(player_id: int, spawn_state: Dictionary) -> void:
	for peer_id: int in connected_peers:
		spawn_player.rpc_id(peer_id, player_id, spawn_state)
		if player_id != peer_id:
			spawn_player.rpc_id(player_id, peer_id, entity_collection[peer_id].spawn_state)


@rpc("authority", "call_remote", "reliable", 0)
func despawn_player(peer_id: int, delete: bool = false) -> void:
	connected_peers.remove_at(connected_peers.find(peer_id))
	if entity_collection.has(peer_id):
		var player: Entity = entity_collection[peer_id] as Entity
		if delete:
			player.queue_free()
		else:
			remove_child(player)
			
		entity_collection.erase(peer_id)
	for id: int in connected_peers:
		despawn_player.rpc_id(id, peer_id)
#endregion

#region chat
@rpc("any_peer", "call_remote", "reliable", 1)
func player_submit_message(new_message: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	for id: int in connected_peers:
		fetch_message.rpc_id(id, new_message, peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func fetch_message(_message: String, _sender_id: int) -> void:
	pass
#endregion
