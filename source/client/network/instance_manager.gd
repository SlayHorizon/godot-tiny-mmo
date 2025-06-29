class_name InstanceManagerClient
extends Node


signal instance_changed(instance: InstanceClient)

static var instance_manager: InstanceManagerClient

var current_ui: UI
var current_instance: InstanceClient


func _ready() -> void:
	instance_manager = self


@rpc("authority", "call_remote", "reliable", 0)
func charge_new_instance(map_path: String, instance_id: String) -> void:
	var new_instance: InstanceClient = InstanceClient.new()
	new_instance.name = instance_id
	
	print("Loading new map: %s." % map_path)
	var map: Map = load(map_path).instantiate() as Map
	if not map:
		return
	
	map.ready.connect(
		new_instance.ready_to_enter_instance.rpc_id.bind(1),
		CONNECT_ONE_SHOT
	)
	map.ready.connect(
		instance_changed.emit.bind(new_instance),
		CONNECT_ONE_SHOT
	)
	
	if current_instance:
		if current_instance.local_player:
			current_instance.local_player.reparent(new_instance, false)
		current_instance.queue_free()
	current_instance = new_instance
	
	new_instance.add_child(map, true)
	add_child(new_instance, true)
	
	# Charge different type of UI/HUD and clear old one,
	# for mini game / special instances that would require unique HUD ? 
	
	if current_ui:
		queue_free()
	if not current_ui:
		current_ui = preload("res://source/client/ui/ui.tscn").instantiate()
		add_child(current_ui)
	
