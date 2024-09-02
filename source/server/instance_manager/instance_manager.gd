class_name InstanceManagerServer
extends Node


var online_instances: Dictionary#[
var instance_collection: Array[InstanceResource]
var main_instance: ServerInstance

func _ready() -> void:
	build_instance_collection()
	multiplayer.peer_connected.connect(func(peer_id: int):
		charge_new_instance.rpc_id(peer_id, {
			"instance_name": main_instance.name,
			"map_path": main_instance.instance_resource.map.resource_path
			}
		)
	)
	Server.start_server()


@rpc("authority", "call_remote", "reliable", 0)
func charge_new_instance(_new_instance: Dictionary) -> void:
	pass

func _on_player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper) -> void:
	var peer_id: int = player.name.to_int()
	var instance_resource: InstanceResource = get_instance_resource_from_name(warper.target_instance_name)
	if not instance_resource:
		return
	var target_instance: ServerInstance
	if instance_resource.charged_instances.is_empty():
		await charge_instance(instance_resource)
	target_instance = instance_resource.charged_instances[0]
	if current_instance.connected_peers.has(peer_id):
		current_instance.despawn_player(peer_id, false)
	charge_new_instance.rpc_id(peer_id, {
		"instance_name": target_instance.name,
		"map_path": instance_resource.map.resource_path
		}
	)
	target_instance.awaiting_peers[peer_id] = {
		"player": player,
		"target_id": warper.target_id
	}


func charge_instance(instance_resource: InstanceResource) -> void:
	var new_instance := ServerInstance.new()
	new_instance.name = str(new_instance.get_instance_id())
	new_instance.instance_resource = instance_resource
	add_child(new_instance, true)
	new_instance.player_entered_warper.connect(self._on_player_entered_warper)
	new_instance.load_map(instance_resource.map)
	instance_resource.charged_instances.append(new_instance)
	# Needs rework.
	if instance_resource.instance_name == "MainInstance":
		main_instance = new_instance
	if not new_instance.is_node_ready():
		await new_instance.ready
	
func get_instance_resource_from_name(instance_name) -> InstanceResource:
	for instance_resource in instance_collection:
		if instance_resource.instance_name == instance_name:
			return instance_resource
	return null

func build_instance_collection() -> void:
	for file_path in get_all_file_paths("res://source/common/resources/custom/instance/instance_collection/"):
		instance_collection.append(ResourceLoader.load(file_path))
	for instance_resource: InstanceResource in instance_collection:
		if instance_resource.load_at_startup:
			charge_instance(instance_resource)

func get_all_file_paths(path: String) -> Array[String]:  
	var file_paths: Array[String] = []  
	var dir := DirAccess.open(path)  
	dir.list_dir_begin()  
	var file_name: String = dir.get_next()  
	while file_name != "":
		if '.tres.remap' in file_name:
			file_name = file_name.trim_suffix('.remap')
		var file_path = path + "/" + file_name  
		if dir.current_is_dir():  
			file_paths += get_all_file_paths(file_path)  
		else:  
			file_paths.append(file_path)  
		file_name = dir.get_next()  
	return file_paths
