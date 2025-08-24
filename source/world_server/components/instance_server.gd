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


#var entity_collection: Dictionary = {}#[int, Entity]
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
	
	add_child(synchronizer_manager, true)


func load_map(map_path: String) -> void:
	if instance_map:
		instance_map.queue_free()
	instance_map = load(map_path).instantiate()
	add_child(instance_map)
	#add_child(CameraProbe.new())
	
	ready.connect(func():
		if instance_map.replicated_props_container:
			synchronizer_manager.add_container(1_000_000, instance_map.replicated_props_container)
		for child in instance_map.get_children():
			if child is InteractionArea:
				child.player_entered_interaction_area.connect(self._on_player_entered_interaction_area)
		)


func _on_player_entered_interaction_area(player: Player, interaction_area: InteractionArea) -> void:
	if player.just_teleported:
		return
	if interaction_area is Warper:
		player_entered_warper.emit.call_deferred(player, self, interaction_area)
	if interaction_area is Teleporter:
		if not player.just_teleported:
			player.just_teleported = true
			player.syn.set_by_path(^":position", interaction_area.target.global_position)


@rpc("any_peer", "call_remote", "reliable", 0)
func player_trying_to_change_weapon(weapon_path: String, _side: bool = true) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	# Check if player has the weapon
	
	var player: Player = players_by_peer_id.get(peer_id, null)
	if not player:
		return
	if player.player_resource.inventory.has(weapon_path):
		player.syn.set_by_path(^":weapon_name_right", weapon_path)


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
		fetch_message.rpc_id(peer_id, get_motd(), 1)
	
	player.just_teleported = true
	
	# Add to scene to ensure _ready of children (ASC/Mirror/Synchronizer) ran.
	add_child(player, true)
	players_by_peer_id[peer_id] = player
	
	#NEW
	var syn: StateSynchronizer = player.get_node("StateSynchronizer")
	syn.set_by_path(^":position", instance_map.get_spawn_position(spawn_index))
	syn.set_by_path(^":character_class", player.player_resource.character_class)
	syn.set_by_path(^":display_name", player.player_resource.display_name)
	
	# Register in sync manager AFTER we seeded states.
	synchronizer_manager.add_entity(peer_id, syn)
	synchronizer_manager.register_peer(peer_id)

	var asc: AbilitySystemComponent = player.get_node_or_null(^"AbilitySystemComponent")
	var max_hp: float = player.character_resource.base_health + player.character_resource.health_per_level * player.player_resource.level
	asc.ensure_attr(&"health", max_hp, max_hp)
	asc.ensure_attr(&"mana", 50.0, 50.0)
	asc.ensure_attr(&"armor", 0.0, 0.0)
	
	asc.set_base_max_server(&"health", max_hp) 
	asc.set_base_server(&"armor", 0.0)

	print_debug("baseline server pairs:", syn.capture_baseline())

	connected_peers.append(peer_id)
	_propagate_spawn(peer_id)


func instantiate_player(peer_id: int) -> Player:
	var player_resource: PlayerResource = world_server.connected_players[peer_id]
	var character_resource: CharacterResource = ResourceLoader.load(
		"res://source/common/resources/custom/character/character_collection/" +
		player_resource.character_class + ".tres"
	)
	
	var new_player: Player = PLAYER.instantiate() as Player
	new_player.name = str(peer_id)
	new_player.player_resource = player_resource
	new_player.character_resource = character_resource
	
	var asc: AbilitySystemComponent = new_player.get_node_or_null(^"AbilitySystemComponent")
	var max_hp: float = character_resource.base_health + character_resource.health_per_level * player_resource.level
	asc.ensure_attr(&"health", max_hp, max_hp)
	asc.ensure_attr(&"mana", 50.0, 50.0)
	
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
			remove_child(player)
		players_by_peer_id.erase(peer_id)
	
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
	var player: Player = players_by_peer_id.get(peer_id, null)
	if not player:
		return
	#player.get_node(^"AbilitySystemComponent")
	const THORNMAIL = preload("res://source/common/combat/equipable_item/resources/thornmail.tres")
	print_debug(player.equipment_component._slots)
	if not player.equipment_component._slots.has(&"chest"):
		player.equipment_component.equip(&"chest", THORNMAIL)
	if player.equipped_weapon_right.try_perform_action(action_index, action_direction):
		propagate_rpc(player_action.bindv([action_index, action_direction, peer_id]))
	#for connected_peer_id: int in connected_peers:
		#player_action.rpc_id(connected_peer_id, action_index, action_direction)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_data(data_type: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	var player: Player = players_by_peer_id.get(peer_id)
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


# -- Helpers joueurs / synchro ------------------------------------------------

func get_player(peer_id: int) -> Player:
	var p: Player = players_by_peer_id.get(peer_id, null)
	return p


func get_player_syn(peer_id: int) -> StateSynchronizer:
	var p: Player = get_player(peer_id)
	return null if p == null else p.get_node_or_null(^"StateSynchronizer")


## Fixe une propriété arbitraire relative à la racine du Player via le Synchronizer.
## Exemple: ^":scale", ^"Sprite2D:modulate", ^"AbilitySystemComponent/AttributesMirror:health"
func set_player_path_value(peer_id: int, rel_path: NodePath, value: Variant) -> bool:
	var syn: StateSynchronizer = get_player_syn(peer_id)
	if syn == null:
		return false
	syn.set_by_path(rel_path, value)  # applique local + marque dirty
	return true


## API “propre” pour les attributs (serveur = source de vérité).
## Utilise l’ASC si présent ; sinon fallback en poussant le miroir.
func set_player_attr_current(peer_id: int, attr: StringName, value: float) -> bool:
	var p: Player = get_player(peer_id)
	if p == null:
		return false

	var asc: AbilitySystemComponent = p.get_node_or_null(^"AbilitySystemComponent")
	if asc != null and asc.has_method("set_attr_current"):
		asc.set_attr_current(attr, value)
		return true

	# Fallback (si pas encore d'API ASC dédiée) : pousser le miroir côté client.
	var np := NodePath("AbilitySystemComponent/AttributesMirror:" + String(attr))
	return set_player_path_value(peer_id, np, value)
