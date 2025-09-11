class_name ServerInstance
extends SubViewport


signal player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper)

const PLAYER: PackedScene = preload("res://source/common/gameplay/characters/player/player.tscn")

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
func try_to_equip_item(item_id: int, _slot_id: int) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	# Check if player has the weapon
	
	var player: Player = players_by_peer_id.get(peer_id, null)
	if player and player.player_resource.inventory.has(item_id):
		var item: GearItem = ContentRegistryHub.load_by_id(&"gears", item_id)
		if item.can_equip(player):
			player.equipment_component.equip(item.slot.key, item)
		#var slot: ItemSlot = ContentRegistryHub.load_by_id(&"item_slots", slot_id)
	#if player.player_resource.inventory.has(weapon_path):
	#player.syn.set_by_path(^":weapon_name_right", weapon_path)


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
	add_child(player, true)
	players_by_peer_id[peer_id] = player
	
	#NEW
	var syn: StateSynchronizer = player.syn
	player.state_synchronizer.set_by_path(^":position", instance_map.get_spawn_position(spawn_index))

	print_debug("baseline server pairs:", syn.capture_baseline())
	
	# Register in sync manager AFTER we seeded states.
	synchronizer_manager.add_entity(peer_id, syn)
	synchronizer_manager.register_peer(peer_id)

	connected_peers.append(peer_id)
	_propagate_spawn(peer_id)


func instantiate_player(peer_id: int) -> Player:
	var player_resource: PlayerResource = world_server.connected_players[peer_id]
	var character_resource: CharacterResource = ResourceLoader.load(
		"res://source/common/gameplay/characters/classes/character_collection/" +
		player_resource.character_class + ".tres"
	)
	
	var new_player: Player = PLAYER.instantiate() as Player
	new_player.name = str(peer_id)
	new_player.player_resource = player_resource
	new_player.character_resource = character_resource
	
	new_player.ready.connect(func():
		var syn: StateSynchronizer = new_player.state_synchronizer
		syn.set_by_path(^":character_class", new_player.player_resource.character_class)
		syn.set_by_path(^":display_name", new_player.player_resource.display_name)
		

		var asc: AbilitySystemComponent = new_player.ability_system_component
		var base_stats: Dictionary = new_player.character_resource.build_base_stats(new_player.player_resource.level)
		
		for stat_name: StringName in base_stats:
			var value: float = base_stats[stat_name]
			if stat_name.ends_with("_max"):
				var base_attr: StringName = stat_name.trim_suffix(&"_max")
				asc.ensure_attr(base_attr, value, value)
				asc.set_max_server(base_attr, value, true)
				asc.set_value_server(base_attr, value)
			else:
				asc.ensure_attr(stat_name, value, value)
				asc.set_value_server(stat_name, value)
		asc.install_resources(new_player.character_resource.power_resources, base_stats)
	,
	CONNECT_ONE_SHOT)
	
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
	propagate_rpc(fetch_message.bindv([new_message, peer_id]))


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
	peer_id = multiplayer.get_remote_sender_id()
	var player: Player = players_by_peer_id.get(peer_id, null)
	if not player:
		return
	
	# Fast item test
	const THORNMAIL = preload("res://source/common/gameplay/items/gears/thornmail.tres")
	player.equipment_component.equip(THORNMAIL.slot.key, THORNMAIL)
	
	
	if player.equipped_weapon_right.try_perform_action(action_index, action_direction):
		propagate_rpc(player_action.bindv([action_index, action_direction, peer_id]))



# Quick and dirty for fast proto test
@rpc("any_peer", "call_remote", "reliable", 1)
func data_request(request_id: int, data_type: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	var player: Player = players_by_peer_id.get(peer_id)
	if not player:
		return
	match data_type:
		"guild/self":
			var guild: Guild = player.player_resource.guild
			var result: String
			if guild:
				result = guild.guild_name
			else:
				result = ""
			data_response.rpc_id(
				peer_id,
				request_id,
				{"guild": result},
			)
		"inventory":
			data_response.rpc_id(
				peer_id,
				request_id,
				player.player_resource.inventory,
			)
	if data_type.begins_with("guild"):
		if data_type.begins_with("guild/search/"):
			const MAX_RESULT: int = 10
			var i: int = 0
			var result: Dictionary
			var guild_names: PackedStringArray = world_server.database.player_data.guilds.keys()
			var to_search: String = data_type.trim_prefix("guild/search/").to_lower()
			for guild_name: String in guild_names:
				if guild_name.to_lower().contains(to_search):
					result[guild_name] = 0
				if i >= MAX_RESULT:
					break
				i += 1
			data_response.rpc_id(peer_id, request_id, result)
		elif data_type.begins_with("guild/get/"):
			var to_get: String = data_type.trim_prefix("guild/get/")
			var guild: Guild = world_server.database.player_data.guilds.get(to_get)
			var guild_info: Dictionary
			if guild:
				guild_info = {"name": guild.guild_name, "size": guild.members.size()}
			data_response.rpc_id(peer_id, request_id, guild_info)
			
			


@rpc("authority", "call_remote", "reliable", 1)
func data_response(_request_id: int, _data: Dictionary) -> void:
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
