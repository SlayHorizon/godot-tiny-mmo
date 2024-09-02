class_name InstanceResource
extends Resource

@export var instance_name: StringName
@export var map: PackedScene
@export var load_at_startup: bool = false
var charged_instances: Array[ServerInstance]
