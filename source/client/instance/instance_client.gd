class_name InstanceClient
extends Node2D

const LOCAL_PLAYER = preload("res://source/client/local_player/local_player.tscn")
const DUMMY_PLAYER = preload("res://source/common/entities/player/player.tscn")

var entity_collection: Dictionary = {}

var last_state: Dictionary = {"T" = 0.0}

var local_player: LocalPlayer

@rpc("authority", "call_remote", "unreliable", 0)
func fetch_instance_state(new_state: Dictionary):
	if new_state["T"] > last_state["T"]:
		last_state = new_state
		update_entity_collection(new_state["EC"]) #EC=EntityCollection

func update_entity_collection(collection_state: Dictionary) -> void:
	collection_state.erase(Client.peer_id)
	for entity_id: int in collection_state:
		if entity_collection.has(entity_id):
			(entity_collection[entity_id] as Entity).sync_state = collection_state[entity_id]
		#else:
			#ask_to_spawn_player() ?

@rpc("any_peer", "call_remote", "unreliable", 0)
func fetch_player_state(_sync_state: Dictionary):
	pass

@rpc("authority", "call_remote", "reliable", 1)
func update_entity(entity_id, to_update: Dictionary) -> void:
	var entity: Entity = entity_collection[entity_id]
	for thing in to_update:
		entity.set_indexed(thing, to_update[thing])

@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(player_id: int, spawn_state: Dictionary) -> void:
	var new_player: Player
	if player_id == Client.peer_id and not local_player:
		new_player = LOCAL_PLAYER.instantiate()
		(new_player as LocalPlayer).sync_state_defined.connect(
			func(sync_state: Dictionary):
				fetch_player_state.rpc_id(1, sync_state)
		)
	else:
		new_player = DUMMY_PLAYER.instantiate()
	new_player.name = str(player_id)
	new_player.spawn_state = spawn_state
	
	entity_collection[player_id] = new_player
	
	add_child(new_player)

@rpc("authority", "call_remote", "reliable", 0)
func despawn_player(player_id: int) -> void:
	if entity_collection.has(player_id):
		(entity_collection[player_id] as Entity).queue_free()
		entity_collection.erase(player_id)

@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	ready_to_enter_instance.rpc_id(1)
