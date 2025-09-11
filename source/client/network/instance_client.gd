class_name InstanceClient
extends Node


const LOCAL_PLAYER: PackedScene = preload("res://source/client/local_player/local_player.tscn")
const DUMMY_PLAYER: PackedScene = preload("res://source/common/gameplay/characters/player/player.tscn")

static var current: InstanceClient
static var local_player: LocalPlayer

var players_by_peer_id: Dictionary[int, Player]

var synchronizer_manager: StateSynchronizerManagerClient
var instance_map: Map


func _ready() -> void:
	current = self
	Events.message_submitted.connect(
		func(message: String, _channel: int):
			player_submit_message(message)
	)
	
	synchronizer_manager = StateSynchronizerManagerClient.new()
	synchronizer_manager.name = "StateSynchronizerManager"

	if instance_map.replicated_props_container:
		synchronizer_manager.add_container(1_000_000, instance_map.replicated_props_container)

	add_child(synchronizer_manager, true)

#@onready var sync_mgr: StateSynchronizerManagerClient = $"../StateSynchronizerManagerClient"
#@onready var syn: StateSynchronizer = $StateSynchronizer
#@onready var _send_timer := Timer.new()
#var my_eid: int
#
#func _ready() -> void:
	#_send_timer.wait_time = 0.05 # 20 Hz
	#_send_timer.one_shot = false
	#_send_timer.autostart = true
	#_send_timer.timeout.connect(_flush_my_delta)
	#add_child(_send_timer)
#
#func _flush_my_delta() -> void:
	#var pairs: Array = syn.collect_dirty_pairs()
	#if pairs.size() == 0:
		#return
	#sync_mgr.send_my_delta(my_eid, pairs)


@rpc("any_peer", "call_remote", "reliable", 0)
func try_to_equip_item(item_id: int, peer_id: int) -> void:
	var player: Player = players_by_peer_id.get(peer_id, null)
	if not player:
		return
	
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if item:
		if item is WeaponItem:
			player.equipment_component.equip(item.slot.key, item)
		elif item is ConsumableItem:
			item.on_use(player)


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
		local_player.instance_client = self
		local_player.synchronizer_manager = synchronizer_manager
	else:
		new_player = DUMMY_PLAYER.instantiate()
	
	new_player.name = str(player_id)
	
	players_by_peer_id[player_id] = new_player
	
	if not new_player.is_inside_tree():
		add_child(new_player)
		#instance_map.add_child(new_player)
	
	var sync: StateSynchronizer = new_player.state_synchronizer
	synchronizer_manager.add_entity(player_id, sync) 


func add_local_player() -> void:
	pass


@rpc("authority", "call_remote", "reliable", 0)
func despawn_player(player_id: int) -> void:
	synchronizer_manager.remove_entity(player_id)
	
	var player: Player = players_by_peer_id.get(player_id, null)
	if player and player != local_player:
		player.queue_free()
	players_by_peer_id.erase(player_id)
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
	else:
		var player: Player = players_by_peer_id.get(sender_id, null)
		if player:
			sender_name = player.display_name
	Events.message_received.emit(message, sender_name, 0)


@rpc("any_peer", "call_remote", "reliable", 1)
func player_submit_command(_new_command: String) -> void:
	pass
#endregion


# WIP
@rpc("any_peer", "call_remote", "reliable", 1)
func player_action(action_index: int, action_direction: Vector2, peer_id: int = 0) -> void:
	var player: Player = players_by_peer_id.get(peer_id) as Player
	if not player:
		return
	player.equipped_weapon_right.perform_action(action_index, action_direction)


#### WIPP ##
var _next_data_request_id: int
var _pending_data_request: Dictionary[int, Callable]


func request_data(data_type: StringName, handler: Callable) -> int:
	var request_id: int = _next_data_request_id
	_next_data_request_id += 1
	_pending_data_request[request_id] = handler
	data_request.rpc_id(1, request_id, data_type)
	# Return request_id in case you may want to keep track of it for cancelation for example.
	return request_id


func cancel_request_data(request_id: int) -> bool:
	# Dictionary.erase eturns true if the given key existed in the dictionary, otherwise false.
	return _pending_data_request.erase(request_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func data_request(_request_id: int, _data_type: String) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 1)
func data_response(request_id: int, data: Dictionary) -> void:
	var callable: Callable = _pending_data_request.get(request_id, Callable())
	_pending_data_request.erase(request_id)
	if callable.is_valid():
		callable.call(data)
