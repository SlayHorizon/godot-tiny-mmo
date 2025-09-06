@tool
class_name StateSynchronizer
extends Node
### Applies baselines/deltas and tracks local changes using compact Field IDs.
### Wire format for state: pairs = [[fid:int, value], ...].
### Works on both server & client.

@export var root_node: Node
@export var enable_tolerant_compare: bool = true
@export var eps_f32: float = 0.001
@export var eps_vec2_len2: float = 0.0001

# Internal state
# Last applied values (fast lookups, no strings).
var _state_by_id: Dictionary[int, Variant] = {} # fid -> last applied value
# Outgoing dirty map (coalesced per fid).
var _dirty: Dictionary[int, Variant] = {} # fid -> pending value
# Buffer for pairs that arrive before cache/scene is ready.
var _pending_pairs: Array = [] # [[fid, value], ...]

# FieldID -> cache
var _prop_cache: Dictionary[int, PropertyCache] = {}


func _ready() -> void:
	# Resolve a sensible default root.
	if Engine.is_editor_hint():
		if root_node == null:
			root_node = get_parent()
	if root_node == null:
		root_node = self


# Public API: apply (baseline / delta)
# Accept plain Array from the network to avoid casts everywhere.


## Apply a full baseline (resets dirty) and immediately try to flush pending.
func apply_baseline(pairs: Array) -> void:
	_apply_pairs(pairs, true)
	_dirty.clear()
	_try_flush_pending()


## Apply a delta block and try to flush pending (for late-resolved nodes).
func apply_delta(pairs: Array) -> void:
	_apply_pairs(pairs, false)
	_try_flush_pending()


## Convenience: apply locally and mark dirty in one go (gameplay-side).
func set_by_path(path: NodePath, value: Variant) -> void:
	var fid: int = PathRegistry.ensure_id(String(path))
	_ensure_cache_from_np(fid, path) # one-time split+cache
	_apply_with_cache(fid, value) # local apply (hot path)
	_state_by_id[fid] = value
	_dirty[fid] = value


## Drain and clear coalesced dirty pairs.
func collect_dirty_pairs() -> Array:
	if _dirty.is_empty():
		return []
	var out: Array = []
	for fid: int in _dirty: # iterate keys directly (no .keys() allocation)
		out.append([fid, _dirty[fid]])
	_dirty.clear()
	return out


## Snapshot current known state as baseline pairs.
func capture_baseline() -> Array:
	var out: Array = []
	for fid: int in _state_by_id:
		out.append([fid, _state_by_id[fid]])
	return out


# Public API: mark-only (no immediate apply)


## Mark a single property dirty by NodePath (resolves the FieldID via registry).
func mark_dirty_by_path(path: NodePath, value: Variant, only_if_changed: bool = true) -> void:
	var fid: int = PathRegistry.ensure_id(String(path))
	_mark_dirty_internal(fid, value, only_if_changed)


## Mark many properties dirty by NodePath (dictionary {path:String/NodePath: value}).
func mark_dirty_many_by_path(props: Dictionary, only_if_changed: bool = true) -> void:
	for k in props.keys():
		var np: NodePath = k if typeof(k) == TYPE_NODE_PATH else NodePath(String(k))
		mark_dirty_by_path(np, props[k], only_if_changed)


## Mark a single property dirty by FieldID (when you already know the ID).
func mark_dirty_by_id(fid: int, value: Variant, only_if_changed: bool = true) -> void:
	_mark_dirty_internal(fid, value, only_if_changed)


## Mark many properties dirty by FieldID (pairs = [[fid, value], ...]).
func mark_many_by_id(pairs: Array, only_if_changed: bool = true) -> void:
	for pair: Array in pairs:
		# Guard is cheap and prevents bad payloads from crashing.
		if pair.size() < 2:
			continue
		_mark_dirty_internal(pair[0], pair[1], only_if_changed)


# Internals


## Set dirty (with optional tolerant comparison) and update local mirror.
func _mark_dirty_internal(fid: int, value: Variant, only_if_changed: bool) -> void:
	if only_if_changed:
		var prev: Variant = _state_by_id.get(fid, null)
		if prev != null and _roughly_equal(fid, prev, value):
			return
	_state_by_id[fid] = value
	_dirty[fid] = value


## Apply a batch of pairs. Unknown fields/nodes get buffered and retried later.
func _apply_pairs(pairs: Array, _is_baseline: bool) -> void:
	for pair: Array in pairs:
		if pair.size() < 2:
			continue
		var fid: int = pair[0]
		var value: Variant = pair[1]
		_state_by_id[fid] = value

		# Try fast path with cache; else ensure cache (from registry) then retry; else buffer.
		if not _apply_with_cache(fid, value):
			if not _ensure_cache_from_registry(fid):
				_pending_pairs.append([fid, value])
			elif not _apply_with_cache(fid, value):
				_pending_pairs.append([fid, value])


## Hot path: uses cached node/prop; re-resolves node if freed.
func _apply_with_cache(fid: int, value: Variant) -> bool:
	var pc: PropertyCache = _prop_cache.get(fid, null)
	if pc == null:
		return false
	return pc.apply_or_try_resolve(root_node, value)


## Build cache from registry (FieldID -> NodePath). Returns true if cache created.
func _ensure_cache_from_registry(fid: int) -> bool:
	var np: NodePath = PathRegistry.nodepath_of(fid)
	if np.is_empty():
		return false
	_ensure_cache_from_np(fid, np)
	return true


## Build/refresh cache from a NodePath. Pre-resolve to root when node path is empty.
func _ensure_cache_from_np(fid: int, np: NodePath) -> void:
	var pc: PropertyCache = _prop_cache.get(fid, null)
	if pc == null:
		pc = PropertyCache.new()
		_prop_cache[fid] = pc
	pc.node_path = TinyNodePath.get_path_to_node(np)
	pc.prop_path = TinyNodePath.get_path_to_property(np)
	# IMPORTANT: empty node_path means "root_node"
	if pc.node_path.is_empty():
		pc.node = root_node
	else:
		pc.node = null # will resolve on first apply


## Retry any pairs that were buffered due to missing cache or nodes not yet ready.
func _try_flush_pending() -> void:
	if _pending_pairs.is_empty():
		return
	var pending: Array = _pending_pairs
	_pending_pairs = []
	_apply_pairs(pending, false)


## Tolerant equality for floats/vec2 to avoid noisy updates (bandwidth saver).
func _roughly_equal(fid: int, a: Variant, b: Variant) -> bool:
	if not enable_tolerant_compare:
		return a == b
	var wtype: int = PathRegistry.type_of(fid)
	match wtype:
		PathRegistry.WIRE_F32:
			return abs(float(a) - float(b)) < eps_f32
		PathRegistry.WIRE_VEC2_F32:
			return (Vector2(a) - Vector2(b)).length_squared() < eps_vec2_len2
		PathRegistry.WIRE_BOOL, PathRegistry.WIRE_I32, PathRegistry.WIRE_VARIANT:
			return a == b
		_:
			return a == b


# Maintenance / Debug


## Invalidate a single field cache (e.g., after a structural refactor).
func invalidate_cache_for(fid: int) -> void:
	_prop_cache.erase(fid)


## Invalidate all caches (e.g., after big scene reload).
func invalidate_all_caches() -> void:
	_prop_cache.clear()


## Build a debug view: path -> value (computed lazily from registry).
func get_state_debug_by_path() -> Dictionary[String, Variant]:
	var out: Dictionary[String, Variant] = {}
	for fid: int in _state_by_id:
		var path: String = PathRegistry.path_of(fid)
		if path != "":
			out[path] = _state_by_id[fid]
	return out


## Per-field cache: resolve split paths once; keep Node ref and re-resolve if freed.
##
## This inner class manages the caching of node paths and properties for efficient
## state synchronization. It stores a reference to the Node and attempts to re-resolve
## it if the cached reference becomes invalid.
class PropertyCache:
	## The NodePath to the target Node, relative to the root_node.
	var node_path: NodePath
	## The property segment of the NodePath (e.g., ":position", "Sprite2D:scale").
	var prop_path: NodePath
	## The cached Node instance. This may become invalid if the node is freed.
	var node: Node = null

	## Applies a value to the cached node's property. If the cached node reference is
	## invalid, it attempts to re-resolve the node before applying the value.
	func apply_or_try_resolve(root: Node, value: Variant) -> bool:
		if node != null and is_instance_valid(node):
			node.set_indexed(prop_path, value)
			return true
		# IMPORTANT: empty node_path means "root_node"
		if node_path.is_empty():
			node = root
		else:
			node = root.get_node_or_null(node_path)
		if node != null:
			node.set_indexed(prop_path, value)
			return true
		return false
