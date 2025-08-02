class_name InstanceClient
extends Node2D


const LOCAL_PLAYER: PackedScene = preload("res://source/client/local_player/local_player.tscn")
const DUMMY_PLAYER: PackedScene = preload("res://source/common/entities/characters/player/player.tscn")

var entity_collection: Dictionary = {}

var last_state: Dictionary = {"T" = 0.0}

var local_player: LocalPlayer


func _ready() -> void:
	Events.message_submitted.connect(player_submit_message)
	Events.item_icon_pressed.connect(player_trying_to_change_weapon)
	Events.data_requested.connect(request_data)


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


@rpc("authority", "call_remote", "reliable", 1)
func update_node(node_path: NodePath, to_update: Dictionary[NodePath, Variant]) -> void:
	var root: Node = get_node_or_null(node_path)
	if not root:
		return
	var target: Node
	for path: NodePath in to_update:
		target = root.get_node_or_null(TinyNodePath.get_path_to_node(path))
		if not target:
			target = root
			#continue
		target.set_indexed(TinyNodePath.get_path_to_property(path), to_update[path])


@rpc("any_peer", "call_remote", "reliable", 0)
func player_trying_to_change_weapon(weapon_path: String, side: bool = true) -> void:
	player_trying_to_change_weapon.rpc_id(1, weapon_path, side)


@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	pass


#region spawn/despawn
@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(player_id: int, spawn_state: Dictionary) -> void:
	var new_player: Player
	if player_id == multiplayer.get_unique_id() and not local_player:
		new_player = LOCAL_PLAYER.instantiate() as LocalPlayer
		new_player.sync_state_defined.connect(
			func(sync_state: Dictionary) -> void:
				fetch_player_state.rpc_id(1, sync_state)
		)
		new_player.player_action.connect(
			func(action_index: int, action_direction: Vector2) -> void:
				player_action.rpc_id(1, action_index, action_direction)
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
func player_submit_message(message: String) -> void:
	if message.begins_with("/"):
		player_submit_command.rpc_id(1, message)
	else:
		player_submit_message.rpc_id(1, message)


@rpc("authority", "call_remote", "reliable", 1)
func fetch_message(message: String, sender_id: int) -> void:
	var sender_name: String = "Unknown"
	if sender_id == 1:
		sender_name = "Server"
	elif entity_collection.has(sender_id):
		sender_name = (entity_collection[sender_id] as Player).display_name
	Events.message_received.emit(message, sender_name)


@rpc("any_peer", "call_remote", "reliable", 1)
func player_submit_command(_new_command: String) -> void:
	pass
#endregion


# WIP
@rpc("any_peer", "call_remote", "reliable", 1)
func player_action(action_index: int, action_direction: Vector2, peer_id: int = 0) -> void:
	var player: Player = entity_collection.get(peer_id) as Player
	if not player:
		return
	player.equiped_weapon_right.try_perform_action(action_index, action_direction)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_data(data_type: String) -> void:
	request_data.rpc_id(1, data_type)


@rpc("authority", "call_remote", "reliable", 1)
func fetch_data(data: Dictionary, data_type: String) -> void:
	Events.data_received.emit(data, data_type)
