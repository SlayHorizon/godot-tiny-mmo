class_name TinyNodePath
extends Node


static func set_property_collection(root: Node, collection: Dictionary[NodePath, Variant]):
	for path: NodePath in collection:
		var target: Node = root.get_node_or_null(get_path_to_node(path))
		if target:
			target.set_indexed(get_path_to_property(path), collection[path])


static func get_path_to_node(path: NodePath) -> NodePath:
	return path.slice(0, path.get_name_count())


static func get_path_to_property(path: NodePath) -> NodePath:
	return path.slice(path.get_name_count())
