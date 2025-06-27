extends Node


func set_child_processes(root: Node, enable: bool) -> void:
	var process_setters: Array[StringName] = [
		&"set_physics_process",
		&"set_process"
	]
	for setter: StringName in process_setters:
		root.propagate_call(setter, [enable])
	
