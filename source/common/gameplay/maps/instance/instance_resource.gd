class_name InstanceResource
extends Resource


@export var instance_name: StringName
@export_file("*.tscn") var map_path: String
@export var load_at_startup: bool = false

var loading_instances: Array
var charged_instances: Array[ServerInstance]


@warning_ignore("unused_parameter")
func can_join_instance(player: Player, index: int = -1) -> bool:
	return true


func get_instance(index: int = -1) -> ServerInstance:
	if charged_instances.is_empty() or charged_instances.size() <= index:
		return null
	return charged_instances[index]
