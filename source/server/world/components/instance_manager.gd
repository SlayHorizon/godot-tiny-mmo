class_name InstanceManagerServer
extends SubViewportContainer


const INSTANCE_COLLECTION_PATH: String = "res://source/common/gameplay/maps/instance/instance_collection/"
const GLOBAL_COMMANDS_PATH: String = "res://source/server/world/components/chat_command/global_commands/"
## Name of the InstanceResource used as the jail. Create a .tres with
## instance_name = "jail" to enable the jail system.
const JAIL_INSTANCE_NAME: String = "jail"

var loading_instances: Dictionary[InstanceResource, ServerInstance]
var instance_collection: Dictionary[String, InstanceResource]
var default_instance: InstanceResource

@export var world_server: WorldServer


func start_instance_manager() -> void:
	ServerInstance.world_server = world_server
	
	setup_global_commands_and_roles()

	set_instance_collection.call_deferred()
	world_server.multiplayer_api.peer_connected.connect(_on_peer_connected)

	# Timer which will call unload_unused_instances
	var timer: Timer = Timer.new()
	timer.wait_time = 20.0 # 20.0 is for testing, consider increasing it

	timer.autostart = true
	timer.timeout.connect(unload_unused_instances)
	add_sibling(timer)

	# Basing: territory tick — every owning guild earns +1 SG per held flag.
	# Lower this constant temporarily if you want to watch ticks land during testing.
	var territory_tick_timer: Timer = Timer.new()
	territory_tick_timer.wait_time = BasingService.TERRITORY_TICK_SECONDS
	territory_tick_timer.autostart = true
	territory_tick_timer.timeout.connect(func(): BasingService.tick_all_territories(world_server))
	add_sibling(territory_tick_timer)


func setup_global_commands_and_roles() -> void:
	var files: PackedStringArray = FileUtils.get_all_file_at(GLOBAL_COMMANDS_PATH, "*.gd")
	if files.is_empty():
		return
	
	var commands := ServerInstance.global_chat_commands
	for file_path: String in files:
		var command = load(file_path).new()
		commands.set(command.command_name, command)

	var roles := ServerInstance.global_role_definitions
	for role: String in roles:
		var role_data: Dictionary = roles[role]
		var role_commands: Array
		
		for command_name: String in commands:
			var command = commands[command_name]
			if command.command_priority <= role_data.get("priority", 0):
				role_commands.append(command_name)

		role_data['commands'] = role_commands


@rpc("authority", "call_remote", "reliable", 0)
func charge_new_instance(_map_path: String, _instance_id: String) -> void:
	pass


## Deal with player respawn on login. Should replace this with proper map respawn logic later?
func _on_peer_connected(peer_id: int) -> void:
	var player_resource: PlayerResource = world_server.connected_players[peer_id]

	# Jailed players go straight to the jail instance, regardless of where they
	# logged out. If the jail map is missing (not authored yet), fall through
	# to normal spawn so we don't strand them in a black void.
	if JailList.is_jailed(player_resource.account_name):
		var jail_res: InstanceResource = instance_collection.get(JAIL_INSTANCE_NAME, null)
		if jail_res != null:
			var jail_inst: ServerInstance
			if jail_res.charged_instances.is_empty():
				jail_inst = charge_instance(jail_res)
			else:
				jail_inst = jail_res.get_instance(0)
			if jail_inst != null:
				charge_new_instance.rpc_id(peer_id, jail_res.map_path, jail_inst.name)
				jail_inst.awaiting_peers[peer_id] = {}
				return

	var last_instance: InstanceResource = instance_collection.get(player_resource.current_instance, null)

	if not last_instance or last_instance.spawn_override == InstanceResource.SpawnOverride.WORLD:
		charge_new_instance.rpc_id(peer_id, default_instance.map_path, default_instance.charged_instances[0].name)
		return

	match last_instance.spawn_override:
		InstanceResource.SpawnOverride.DEFAULT:
			var instance: ServerInstance
			if last_instance.charged_instances.is_empty():
				instance = charge_instance(last_instance)
			else:
				instance = last_instance.get_instance(0)
			charge_new_instance.rpc_id(peer_id, last_instance.map_path, instance.name)
			instance.awaiting_peers[peer_id] = {"target_position": player_resource.last_position}
		InstanceResource.SpawnOverride.ENTRY:
			# TO DO
			charge_new_instance.rpc_id(peer_id, default_instance.map_path, default_instance.charged_instances[0].name)


func _on_player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper) -> void:
	# Jailed players can't traverse warpers — that's the whole point of jail.
	# We notify them once per attempt so they know it's intentional.
	if JailList.is_jailed(player.player_resource.account_name):
		world_server.chat_service.push_system_to_player(
			current_instance, player.player_resource.player_id,
			"You are jailed and cannot leave this area."
		)
		return

	var instance_index: int = -1 # Will be useful later
	var target_instance: ServerInstance
	var instance_resource: InstanceResource = warper.target_instance
	if not instance_resource:
		return
	
	if instance_resource.can_join_instance(player, instance_index):
		target_instance = instance_resource.get_instance()
		if target_instance:
			player_switch_instance(target_instance, warper.target_id, player, current_instance)
		else:
			queue_charge_instance(
				instance_resource,
				player_switch_instance.bind(warper.target_id, player, current_instance)
			)
	else:
		return


func queue_charge_instance(instance_resource: InstanceResource, callback: Callable) -> void:
	if loading_instances.has(instance_resource):
		loading_instances[instance_resource].ready.connect(
			callback.bind(loading_instances[instance_resource])
		)
		return
	var new_instance: ServerInstance = prepare_instance(instance_resource)
	new_instance.ready.connect(callback.bind(new_instance), CONNECT_ONE_SHOT)
	add_child(new_instance, true)


func player_switch_instance(
	target_instance: ServerInstance,
	warper_target_id: int,
	player: Player,
	current_instance: ServerInstance,
) -> void:
	var peer_id: int = player.name.to_int()
	if current_instance.connected_peers.has(peer_id):
		current_instance.despawn_player(peer_id, false)
	else:
		return
	charge_new_instance.rpc_id(
		peer_id,
		target_instance.instance_resource.map_path,
		target_instance.name
	)
	target_instance.awaiting_peers[peer_id] = {
		"player": player,
		"target_id": warper_target_id
	}


func charge_instance(instance_resource: InstanceResource) -> ServerInstance:
	if loading_instances.has(instance_resource):
		return
	var new_instance: ServerInstance = prepare_instance(instance_resource)
	add_child.call_deferred(new_instance, true)
	return new_instance


func prepare_instance(instance_resource: InstanceResource) -> ServerInstance:
	var instance: ServerInstance = ServerInstance.new()
	loading_instances[instance_resource] = instance
	instance.name = str(instance.get_instance_id())
	instance.instance_resource = instance_resource
	instance.player_entered_warper.connect(_on_player_entered_warper)
	instance.ready.connect(
		func():
			loading_instances.erase(instance_resource)
			instance_resource.charged_instances.append(instance),
		CONNECT_ONE_SHOT
	)
	instance.load_map(instance_resource.map_path)
	return instance


func set_instance_collection() -> void:
	for file_path: String in FileUtils.get_all_file_at(INSTANCE_COLLECTION_PATH, "*.tres"):
		if not file_path.ends_with(".tres"):
			continue
		# No type hint: in exports the custom-class loader isn't guaranteed
		# registered by the time this scan runs, so the hint "InstanceResource"
		# trips the resource loader. Load as untyped Resource and let the
		# embedded script class be resolved at assignment.
		var loaded: Resource = ResourceLoader.load(file_path)
		if loaded == null or not (loaded is InstanceResource):
			continue
		var instance_resource: InstanceResource = loaded
		if instance_resource.load_at_startup:
			charge_instance(instance_resource)
		if instance_resource.instance_name == "Overworld":
			default_instance = instance_resource
		instance_collection.set(instance_resource.instance_name, instance_resource)


func unload_unused_instances() -> void:
	print("Checking unload_unused_instances")
	for instance: ServerInstance in get_children():
		if instance.instance_resource.load_at_startup:
			continue
		if instance.connected_peers:
			continue
		instance.instance_resource.charged_instances.erase(instance)
		instance.queue_free()


func get_instance_server_by_id(id: String) -> ServerInstance:
	if self.has_node(id):
		return self.get_node(id)
	return null


## Look up which ServerInstance a peer is currently in. O(instances) but
## instance counts are small (a few dozen at most), so this is fine for
## staff commands.
func find_instance_for_peer(peer_id: int) -> ServerInstance:
	for res: InstanceResource in instance_collection.values():
		for inst: ServerInstance in res.charged_instances:
			if inst.connected_peers.has(peer_id):
				return inst
	return null


## Move an online player straight to the jail instance. Mirrors the warper
## handler: synchronous switch if jail is already charged, else queue until
## the instance is ready. Silently no-ops if the jail map isn't authored yet.
## Returns true if a teleport was scheduled.
func send_player_to_jail(peer_id: int) -> bool:
	var jail_res: InstanceResource = instance_collection.get(JAIL_INSTANCE_NAME, null)
	if jail_res == null:
		push_warning("send_player_to_jail: no '%s' instance in collection." % JAIL_INSTANCE_NAME)
		return false

	var current_inst: ServerInstance = find_instance_for_peer(peer_id)
	if current_inst == null:
		return false
	var player: Player = current_inst.get_player(peer_id)
	if player == null:
		return false

	# Already in jail — nothing to do.
	if current_inst.instance_resource == jail_res:
		return false

	if jail_res.charged_instances.is_empty():
		queue_charge_instance(
			jail_res,
			player_switch_instance.bind(0, player, current_inst)
		)
	else:
		player_switch_instance(jail_res.get_instance(), 0, player, current_inst)
	return true


## Teleport an online player to an absolute position, in their current instance
## or another one. Used by /goto and /summon. Returns true if scheduled.
##
## Same instance: move server-side state (so other viewers see it) AND push an
## explicit teleport to the moved client — its LocalPlayer owns its position, so
## a state delta alone won't move it (it'd overwrite next input frame).
## Cross instance: despawn here and respawn at the position over there; the fresh
## spawn places the LocalPlayer correctly with no extra push.
func teleport_peer_to(peer_id: int, dest_instance: ServerInstance, dest_position: Vector2) -> bool:
	if dest_instance == null:
		return false
	var current_inst: ServerInstance = find_instance_for_peer(peer_id)
	if current_inst == null:
		return false
	var player: Player = current_inst.get_player(peer_id)
	if player == null:
		return false

	if current_inst == dest_instance:
		player.mark_just_teleported()
		player.state_synchronizer.set_by_path(^":position", dest_position)
		world_server.data_push.rpc_id(peer_id, &"player.teleport", {"position": dest_position})
		return true

	current_inst.despawn_player(peer_id, false)
	charge_new_instance.rpc_id(peer_id, dest_instance.instance_resource.map_path, dest_instance.name)
	dest_instance.awaiting_peers[peer_id] = {"player": player, "target_position": dest_position}
	return true
