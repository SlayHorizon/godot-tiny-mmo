class_name PropertyCache
## Per-field cache: resolve split paths once; keep Node ref and re-resolve if freed.
##
## This inner class manages the caching of node paths and properties for efficient
## state synchronization. It stores a reference to the Node and attempts to re-resolve
## it if the cached reference becomes invalid.

## The NodePath to the target Node, relative to the root_node.
var node_path: NodePath
## The property segment of the NodePath (e.g., ":position", "Sprite2D:scale").
var property_path: NodePath
## The cached Node instance. This may become invalid if the node is freed.
var node: Node


func _init(
	_node_path: NodePath,
	_property_path: NodePath,
	_node: Node
) -> void:
	node_path = _node_path
	property_path = _property_path
	node = _node


## Applies a value to the cached node's property. If the cached node reference is
## invalid, it attempts to re-resolve the node before applying the value.
func apply_or_try_resolve(root: Node, value: Variant) -> bool:
	if node != null and is_instance_valid(node):
		node.set_indexed(property_path, value)
		return true
	# IMPORTANT: empty node_path means "root_node"
	if node_path.is_empty():
		node = root
	else:
		node = root.get_node_or_null(node_path)
	if node != null:
		node.set_indexed(property_path, value)
		return true
	return false


static func ensure_cache_for(
	property_id: int,
	root: Node,
	cache: Dictionary,
	cache_key: Variant = property_id
	) -> PropertyCache:
	var property_cache: PropertyCache = cache.get(cache_key, null)
	if property_cache:
		return property_cache

	var np: NodePath = PathRegistry.nodepath_of(property_id)
	if np.is_empty():
		return null

	property_cache = PropertyCache.new(
		TinyNodePath.get_path_to_node(np),
		TinyNodePath.get_path_to_property(np),
		root if np.is_empty() else null
	)
	cache[cache_key] = property_cache
	return property_cache
