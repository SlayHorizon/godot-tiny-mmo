@tool
class_name StateSynchronizer
extends Node
### Applies baselines/deltas and tracks local changes using compact Field IDs.
### Wire format for state: pairs = [[fid:int, value], ...].
### Works on both server & client.

@export var root_node: Node

# Internal state
# Last applied values (fast lookups, no strings).
# fid -> last applied value
var last_applied: Dictionary[int, Variant]
# Outgoing dirty map (coalesced per fid).
# fid -> pending value
var dirty_outgoing: Dictionary[int, Variant]
# Buffer for pairs that arrive before cache/scene is ready.
# [[fid, value], ...]
var _pending_pairs: Array

# FieldID -> cache
var _prop_cache: Dictionary[int, PropertyCache]


func _ready() -> void:
	# Resolve a sensible default root.
	if Engine.is_editor_hint():
		if root_node == null:
			root_node = get_parent()
		return
	assert(root_node != null, "State Synchronizer isn't mean to be used alone.")


# Public API: apply (baseline / delta)
# Accept plain Array from the network to avoid casts everywhere.


## Apply a full baseline (resets dirty) and immediately try to flush pending.
func apply_baseline(pairs: Array) -> void:
	_apply_pairs(pairs, true)
	dirty_outgoing.clear()
	_try_flush_pending()


## Apply a delta block and try to flush pending (for late-resolved nodes).
func apply_delta(pairs: Array) -> void:
	_apply_pairs(pairs, false)
	_try_flush_pending()


## Convenience: apply locally and mark dirty in one go (gameplay-side).
func set_by_path(path: NodePath, value: Variant) -> void:
	var fid: int = PathRegistry.ensure_id(String(path))
	var property_cache: PropertyCache = PropertyCache.ensure_cache_for(fid, root_node, _prop_cache)
	if property_cache:
		property_cache.apply_or_try_resolve(root_node, value)
	last_applied[fid] = value
	dirty_outgoing[fid] = value


## Drain and clear coalesced dirty pairs.
func collect_dirty_pairs() -> Array:
	if dirty_outgoing.is_empty():
		return []
	var out: Array = []
	for fid: int in dirty_outgoing:
		out.append([fid, dirty_outgoing[fid]])
	dirty_outgoing.clear()
	return out


## Snapshot current known state as baseline pairs.
func capture_baseline() -> Array:
	var out: Array = []
	for fid: int in last_applied:
		out.append([fid, last_applied[fid]])
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
		var prev: Variant = last_applied.get(fid, null)
		if prev != null and SyncUtils.roughly_equal(prev, value):
			return
	last_applied[fid] = value
	dirty_outgoing[fid] = value


## Apply a batch of pairs. Unknown fields/nodes get buffered and retried later.
func _apply_pairs(pairs: Array, _is_baseline: bool) -> void:
	for pair: Array in pairs:
		if pair.size() < 2:
			continue
		var fid: int = pair[0]
		var value: Variant = pair[1]
		last_applied[fid] = value

		var property_cache: PropertyCache = PropertyCache.ensure_cache_for(fid, root_node, _prop_cache) 
		if property_cache == null or not property_cache.apply_or_try_resolve(root_node, value):
			_pending_pairs.append([fid, value])


## Retry any pairs that were buffered due to missing cache or nodes not yet ready.
func _try_flush_pending() -> void:
	if _pending_pairs.is_empty():
		return
	var pending: Array = _pending_pairs
	_pending_pairs = []
	_apply_pairs(pending, false)

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
	for fid: int in last_applied:
		var path: String = PathRegistry.path_of(fid)
		if path != "":
			out[path] = last_applied[fid]
	return out
