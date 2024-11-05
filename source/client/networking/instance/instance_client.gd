class_name InstanceClient
extends Node2D


const LOCAL_PLAYER = preload("res://source/client/local_player/local_player.tscn")
const DUMMY_PLAYER = preload("res://source/common/entities/characters/player/player.tscn")

var entity_collection: Dictionary = {}

var last_state: Dictionary = {"T" = 0.0}

var local_player: LocalPlayer


func _ready() -> void:
	ClientEvents.message_entered.connect(self.player_submit_message)
	ClientEvents.item_icon_pressed.connect(self.player_trying_to_change_weapon)


@rpc("authority", "call_remote", "reliable", 0)
func fetch_instance_state(new_state: Dictionary):
	if new_state["T"] > last_state["T"]:
		last_state = new_state
		update_entity_collection(new_state["EC"]) #EC=EntityCollection


func update_entity_collection(collection_state: Dictionary) -> void:
	collection_state.erase(multiplayer.get_unique_id())
	for entity_id: int in collection_state:
		if entity_collection.has(entity_id):
			(entity_collection[entity_id] as Entity).sync_state = collection_state[entity_id]
		#else:
			#ask_to_spawn_player() ?


@rpc("any_peer", "call_remote", "reliable", 0)
func fetch_player_state(_sync_state: Dictionary):
	pass


@rpc("authority", "call_remote", "reliable", 1)
func update_entity(entity_id: int, to_update: Dictionary) -> void:
	var entity: Entity = entity_collection[entity_id]
	for thing in to_update:
		entity.set_indexed(thing, to_update[thing])


@rpc("any_peer", "call_remote", "reliable", 0)
func player_trying_to_change_weapon(weapon_path: String, side: bool = true) -> void:
	player_trying_to_change_weapon.rpc_id(1, weapon_path, side)


@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	ready_to_enter_instance.rpc_id(1)

#region spwawn/despawn
@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(player_id: int, spawn_state: Dictionary) -> void:
	var new_player: Player
	if player_id == multiplayer.get_unique_id() and not local_player:
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
#endregion

#region chat
@rpc("any_peer", "call_remote", "reliable", 1)
func player_submit_message(new_message: String) -> void:
	player_submit_message.rpc_id(1, new_message)


@rpc("authority", "call_remote", "reliable", 1)
func fetch_message(message: String, sender_id: int) -> void:
	var sender_name: String = "Unknown"
	if sender_id == 1:
		sender_name = "Server"
	elif entity_collection.has(sender_id):
		sender_name = (entity_collection[sender_id] as Player).display_name
	ClientEvents.message_received.emit(message, sender_name)
#endregion
