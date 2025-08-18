@tool
class_name StateSynchronizer
extends Node
## Applies baselines/deltas and tracks local changes using compact field IDs.
## Wire format: pairs = [[pid:int, value], ...].

@export var root_node: Node
@export var enable_node_cache: bool = true

var _state: Dictionary[String, Variant] = {}          # last applied values keyed by path string
var _dirty: Dictionary[int, Variant] = {}             # pending deltas (pid -> value)
var _node_cache: Dictionary[NodePath, Node] = {}      # cache by node-only path (no property segment)


func _ready() -> void:
	if Engine.is_editor_hint():
		if root_node == null:
			root_node = get_parent()
	if root_node == null:
		root_node = self


# --- Public API: apply (baseline/delta) --------------------------------------


func apply_baseline(pairs: Array) -> void:
	_apply_pairs(pairs)
	_dirty.clear()


func apply_delta(pairs: Array) -> void:
	_apply_pairs(pairs)


## Convenience: apply and mark in one go (gameplay that sets properties here).
func set_by_path(path: NodePath, value: Variant) -> void:
	var pid: int = PathRegistry.ensure_id(String(path))
	_apply_single_np(path, value)
	_state[String(path)] = value
	_dirty[pid] = value


func collect_dirty_pairs() -> Array:
	if _dirty.is_empty():
		return []
	var out: Array = []
	for pid in _dirty.keys():
		out.append([pid, _dirty[pid]])
	_dirty.clear()
	return out


func capture_baseline() -> Array:
	var out: Array = []
	for k in _state.keys():
		var path_str: String = String(k)
		var pid: int = PathRegistry.ensure_id(path_str)
		out.append([pid, _state[path_str]])
	return out


# --- Public API: mark-only (no apply) ----------------------------------------


## Mark a single property as dirty by NodePath, without applying to the scene.
func mark_dirty_by_path(path: NodePath, value: Variant, only_if_changed: bool = true) -> void:
	var path_str: String = String(path)
	var pid: int = PathRegistry.ensure_id(path_str)
	_mark_dirty_internal(pid, path_str, value, only_if_changed)


## Mark many properties as dirty by NodePath (dictionary {path:String/NodePath: value}).
func mark_dirty_many_by_path(props: Dictionary, only_if_changed: bool = true) -> void:
	for k in props.keys():
		var path_np: NodePath = k if typeof(k) == TYPE_NODE_PATH else NodePath(String(k))
		mark_dirty_by_path(path_np, props[k], only_if_changed)


## Mark a property as dirty by pid (when tu connais déjà l’ID).
func mark_dirty_by_id(pid: int, value: Variant, only_if_changed: bool = true) -> void:
	var path_str: String = PathRegistry.path_of(pid)
	# Si on ne connaît pas le path, on marque quand même dirty (au pire _state ne sera pas tenu à jour).
	if path_str == "":
		_dirty[pid] = value
		return
	_mark_dirty_internal(pid, path_str, value, only_if_changed)


## Mark a list of pid/value pairs as dirty (pairs = [[pid:int, value], ...]).
func mark_many_by_id(pairs: Array, only_if_changed: bool = true) -> void:
	var count: int = pairs.size()
	for i in range(count):
		var p: Array = pairs[i]
		if p.size() < 2:
			continue
		var pid: int = int(p[0])
		var value: Variant = p[1]
		mark_dirty_by_id(pid, value, only_if_changed)


# --- Internals ----------------------------------------------------------------


func _mark_dirty_internal(pid: int, path_str: String, value: Variant, only_if_changed: bool) -> void:
	if only_if_changed:
		var prev: Variant = _state.get(path_str, null)
		if prev == value:
			return
	_state[path_str] = value
	_dirty[pid] = value


func _apply_pairs(pairs: Array) -> void:
	if not multiplayer.is_server():
		print(pairs)
	var count: int = pairs.size()
	for i in range(count):
		var p: Array = pairs[i]
		if p.size() < 2:
			continue
		var pid: int = int(p[0])
		var value: Variant = p[1]

		var np: NodePath = PathRegistry.nodepath_of(pid)
		if np.is_empty():
			continue
		_apply_single_np(np, value)
		_state[String(np)] = value


func _apply_single_np(np: NodePath, value: Variant) -> void:
	var node_only: NodePath = TinyNodePath.get_path_to_node(np)
	var target: Node = _get_target_node(node_only)
	if target != null:
		var prop_path: NodePath = TinyNodePath.get_path_to_property(np)
		target.set_indexed(prop_path, value)


func _get_target_node(node_only_path: NodePath) -> Node:
	if node_only_path.is_empty():
		return root_node
	
	if not enable_node_cache:
		return root_node.get_node_or_null(node_only_path)

	var cached: Node = _node_cache.get(node_only_path, null)
	if cached != null and is_instance_valid(cached):
		return cached

	var resolved: Node = root_node.get_node_or_null(node_only_path)
	if resolved != null:
		_node_cache[node_only_path] = resolved
	return resolved


var containers: Dictionary[int, ReplicatedPropsContainer] = {}  # eid -> container
var _pending_cont_bootstrap: Array = []                         # bytes à rejouer si container pas encore add

func add_container(eid: int, container: ReplicatedPropsContainer) -> void:
	containers[eid] = container

@rpc("authority", "reliable")
func on_props_bootstrap(bytes: PackedByteArray) -> void:
	var msg: Dictionary = WireCodec.decode_container_block(bytes)
	var eid: int = int(msg.get("eid", -1))
	var cont: ReplicatedPropsContainer = containers.get(eid, null)
	if cont == null:
		_pending_cont_bootstrap.append(bytes)
		return
	cont.apply_spawns(msg.get("spawns", []))
	cont.apply_pairs(msg.get("pairs", []))
	cont.apply_despawns(msg.get("despawns", []))
	cont.reveal_after_baseline()

@rpc("authority", "reliable")
func on_props_delta(bytes: PackedByteArray) -> void:
	var msg: Dictionary = WireCodec.decode_container_block(bytes)
	var eid: int = int(msg.get("eid", -1))
	var cont: ReplicatedPropsContainer = containers.get(eid, null)
	if cont == null:
		# si le conteneur n'est pas encore présent, on peut bufferiser si tu veux
		_pending_cont_bootstrap.append(bytes)
		return
	cont.apply_spawns(msg.get("spawns", []))
	cont.apply_pairs(msg.get("pairs", []))
	cont.apply_despawns(msg.get("despawns", []))
