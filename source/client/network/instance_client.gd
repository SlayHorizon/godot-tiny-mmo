class_name InstanceClient
extends Node2D


const LOCAL_PLAYER: PackedScene = preload("res://source/client/local_player/local_player.tscn")
const DUMMY_PLAYER: PackedScene = preload("res://source/common/gameplay/characters/player/player.tscn")


var players_by_peer_id: Dictionary[int, Player]

var last_state: Dictionary = {"T" = 0.0}

static var local_player: LocalPlayer
var synchronizer_manager: StateSynchronizerManagerClient
var instance_map: Map


func _ready() -> void:
	Events.message_submitted.connect(
		func(message: String, _channel: int):
			player_submit_message(message)
	)
	Events.item_icon_pressed.connect(player_trying_to_change_weapon)
	Events.data_requested.connect(request_data)
	
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
func player_trying_to_change_weapon(weapon_path: String, side: bool = true) -> void:
	player_trying_to_change_weapon.rpc_id(1, weapon_path, side)


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


@rpc("any_peer", "call_remote", "reliable", 1)
func request_data(data_type: String) -> void:
	request_data.rpc_id(1, data_type)


@rpc("authority", "call_remote", "reliable", 1)
func fetch_data(data: Dictionary, data_type: String) -> void:
	Events.data_received.emit(data, data_type)
