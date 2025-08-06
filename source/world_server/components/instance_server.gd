class_name ServerInstance
extends SubViewport


signal player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper)

const PLAYER: PackedScene = preload("res://source/common/entities/characters/player/player.tscn")

static var world_server: WorldServer

static var global_chat_commands: Dictionary[String, ChatCommand]
static var global_role_definitions: Dictionary[String, Dictionary]

var local_chat_commands: Dictionary[String, ChatCommand]
var local_role_definitions: Dictionary[String, Dictionary]
var local_role_assignments: Dictionary[int, PackedStringArray]


var entity_collection: Dictionary = {}#[int, Entity]
## Current connected peers to the instance.
var connected_peers: PackedInt64Array = PackedInt64Array()
## Peers coming from another instance.
var awaiting_peers: Dictionary = {}#[int, Player]

var last_accessed_time: float

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
		player_entered_warper.emit.call_deferred(player, self, interaction_area)
	if interaction_area is Teleporter:
		if not player.just_teleported:
			player.just_teleported = true
			update_node(
				get_path_to(player),
				{^":position": interaction_area.target.global_position}
			)



@rpc("authority", "call_remote", "reliable", 1)
func update_node(node_path: NodePath, to_update: Dictionary[NodePath, Variant]) -> void:
	var root: Node = get_node_or_null(node_path)
	if not root:
		return
	var target: Node
	var target_path: NodePath
	for path: NodePath in to_update:
		target_path = TinyNodePath.get_path_to_node(path)
		if target_path:
			target = root.get_node_or_null(target_path)
		else:
			target = root
		if not target:
			continue
		target.set_indexed(TinyNodePath.get_path_to_property(path), to_update[path])
		root.spawn_state[path] = to_update[path]
	
	for peer_id: int in connected_peers:
		update_node.rpc_id(peer_id, node_path, to_update)


@rpc("authority", "call_remote", "reliable", 1)
func update_entity(entity: Entity, to_update: Dictionary) -> void:
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
	#var entity: Entity = entity_collection[peer_id] as Entity
	var player: Player = entity_collection[peer_id] as Player
	if not player:
		return
	if player.player_resource.inventory.has(weapon_path):
		update_node(
			player.get_path(), 
			{^":weapon_name_right": weapon_path}
		)


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
		fetch_message.rpc_id(peer_id, get_motd(), 1)
	player.spawn_state[":position"] = instance_map.get_spawn_position(spawn_index)
	player.just_teleported = true
	add_child(player, true)
	entity_collection[peer_id] = player
	connected_peers.append(peer_id)
	propagate_spawn(peer_id, player.spawn_state)

func get_motd() -> String:
	return world_server.world_manager.world_info.get("motd", "Default Welcome")

func instantiate_player(peer_id: int) -> Player:
	var player_resource: PlayerResource = world_server.connected_players[peer_id]
	var character_resource: CharacterResource = ResourceLoader.load(
		"res://source/common/resources/custom/character/character_collection/" +
		player_resource.character_class + ".tres"
	)
	var new_player: Player = PLAYER.instantiate() as Player
	new_player.name = str(peer_id)
	new_player.player_resource = player_resource
	new_player.spawn_state = {
		"character_class": player_resource.character_class,
		"display_name": player_resource.display_name,
		"health_component:health": character_resource.base_health + character_resource.health_per_level * player_resource.level,
		"health_component:max_health": character_resource.base_health + character_resource.health_per_level * player_resource.level,
	}
	print(new_player.spawn_state)
	return new_player

## Spawn the new player on all other client in the current instance
## and spawn all other players on the new client.
func propagate_spawn(player_id: int, spawn_state: Dictionary) -> void:
	#propagate_rpc(spawn_player)
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
	# Not sure if this new version is better.
	# NEW
	propagate_rpc(fetch_message.bindv([new_message, peer_id]))
	# OLD
	#for id: int in connected_peers:
		#fetch_message.rpc_id(id, new_message, peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func fetch_message(_message: String, _sender_id: int) -> void:
	pass


@rpc("any_peer", "call_remote", "reliable", 1)
func player_submit_command(command: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not command.begins_with("/"):
		return
	var args: PackedStringArray = command.split(" ")
	var command_name: String = args[0]
	var chat_command: ChatCommand = find_command(command_name)
	if chat_command and has_command_permission(command_name, peer_id):
		fetch_message.rpc_id(
			peer_id,
			chat_command.execute(args, peer_id, self),
			1
		)
	else:
		fetch_message.rpc_id(peer_id, "Command not found.", 1)


func find_command(command_name: String) -> ChatCommand:
	if local_chat_commands.has(command_name):
		return local_chat_commands.get(command_name)
	return global_chat_commands.get(command_name)


# Can be refactored to be more efficient?
func has_command_permission(command_name: String, peer_id: int) -> bool:
	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if not player:
		return false
	
	# Check if command is possible by default.
	# Check in current instance.
	var default_role_data: Dictionary = local_role_definitions.get("default", {})
	if default_role_data and command_name in default_role_data.get("commands", []):
		return true
	
	# Check server-wide.
	default_role_data = global_role_definitions.get("default", {})
	if default_role_data and command_name in default_role_data.get("commands", []):
		return true
	
	# Check if player has roles in current instance.
	for role: String in local_role_assignments.get(peer_id, []):
		var role_data: Dictionary = local_role_definitions.get(role)
		if role_data and command_name in role_data.get("commands", []):
			return true
		# Check if role is defined locally.
		if local_role_definitions.has(role) and local_role_definitions[role].has("commands"):
			# Check if roole has permission.
			if local_role_definitions[role]["commands"].has(command_name):
				return true
	
	# Same but for server-wide roles.
	for role: String in player.server_roles:
		var role_data: Dictionary = global_role_definitions.get(role)
		if role_data and command_name in role_data.get("commands", []):
			return true
	return false
#endregion


# WIP
@rpc("any_peer", "call_remote", "reliable", 1)
func player_action(action_index: int, action_direction: Vector2, peer_id: int = 0) -> void:
	#var peer_id: int = multiplayer.get_remote_sender_id()
	peer_id = multiplayer.get_remote_sender_id()
	var player: Player = entity_collection.get(peer_id) as Player
	if not player:
		return
	if player.equipped_weapon_right.try_perform_action(action_index, action_direction):
		propagate_rpc(player_action.bindv([action_index, action_direction, peer_id]))
	#for connected_peer_id: int in connected_peers:
		#player_action.rpc_id(connected_peer_id, action_index, action_direction)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_data(data_type: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	var player: Player = entity_collection.get(peer_id) as Player
	if not player:
		return
	match data_type:
		"guild":
			var guild: Guild = player.player_resource.guild
			var result: String
			if guild:
				result = guild.guild_name
			else:
				result = ""
			fetch_data.rpc_id(
				peer_id,
				{"guild": result},
				"guild"
			)


@rpc("authority", "call_remote", "reliable", 1)
func fetch_data(_data: Dictionary, _data_type: String) -> void:
	pass


func propagate_rpc(callable: Callable) -> void:
	for peer_id: int in connected_peers:
		callable.rpc_id(peer_id)
