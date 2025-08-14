@tool
class_name ReplicatedPropsContainer
extends Node
## Container for “cold” scene props (static & dynamic).
## - Batches property pairs, dynamic spawns/despawns, and *named ops* (rp_*).
## - Baseline for late joiners can be built from named ops (scene-owned logic).

@export var synchronizer: StateSynchronizer

@export_tool_button("Bake") var callback: Callable = _bake_static_map
@export var id_to_relpath: Dictionary[int, NodePath] = {}   # baked in editor

const STATIC_MAX: int = 32767

var _node_cache: Dictionary[NodePath, Node] = {}            # static nodes cache by relpath
@export var _relpath_to_id: Dictionary[NodePath, int] = {}          # reverse map for static lookups

# Dynamic registry
var _dyn_nodes: Dictionary[int, Node] = {}                  # child_id -> Node
var _dyn_info: Dictionary[int, int] = {}                    # child_id -> scene_id  (for bootstrap)
var _next_dyn_id: int = STATIC_MAX + 1

# Outgoing queues (server tick)
var _dyn_spawns_queued: Array = []                          # [[child_id:int, scene_id:int], ...]
var _dyn_despawns_queued: Array = []                        # [child_id:int, ...]
var _ops_named_queued: Array = []                           # [[child_id:int, method:String, args:Array], ...]

# Baseline-by-ops (server truth for statics or long-lived dyns)
# child_id -> [[method:String, args:Array], ...]
var _baseline_ops_by_child: Dictionary[int, Array] = {}


func _ready() -> void:
	if Engine.is_editor_hint() and id_to_relpath.is_empty():
		_bake_static_map()
		return
		
	# Build reverse map for statics and tag descendants for O(1) access from props.
	for id in id_to_relpath.keys():
		_relpath_to_id[id_to_relpath[id]] = int(id)
	_tag_descendants(self)

func _bake_static_map() -> void:
	id_to_relpath.clear()
	_relpath_to_id.clear()
	var id: int = 0
	var path: NodePath
	for child: Node in find_children("Coin*"):
		path = self.get_path_to(child)
		id_to_relpath[id] = path
		_relpath_to_id[path] = id
		id += 1

# --- Client-side apply --------------------------------------------------------


func apply_spawns(spawns: Array) -> void:
	for s in spawns:
		var child_id: int = int(s[0])
		var scene_id: int = int(s[1])
		if _resolve_child(child_id) != null:
			_dyn_info[child_id] = scene_id
			continue
		var scene_path: String = SceneRegistry.path_of(scene_id)
		var inst: Node = load(scene_path).instantiate()
		add_child(inst)
		_dyn_nodes[child_id] = inst
		_dyn_info[child_id] = scene_id
		# New subtree gets tagged so children can reach the container fast.
		_tag_descendants(inst)


func apply_pairs(pairs: Array) -> void:
	for p in pairs:
		if p.size() < 2:
			continue
		var cpid: int = int(p[0])
		var value: Variant = p[1]
		var child_id: int = (cpid >> 16) & 0xFFFF
		var fid: int = cpid & 0xFFFF

		var root: Node = _resolve_child(child_id)
		if root == null:
			continue

		var rel_np: NodePath = PathRegistry.nodepath_of(fid) # relative to child
		if rel_np.is_empty():
			continue

		var target: Node = _resolve_under(root, TinyNodePath.get_path_to_node(rel_np))
		if target != null:
			target.set_indexed(TinyNodePath.get_path_to_property(rel_np), value)


func apply_ops_named(ops_named: Array) -> void:
	# Named ops: [[child_id, method:String, args:Array], ...]
	for o in ops_named:
		print(o)
		if o.size() < 2:
			continue
		var child_id: int = int(o[0])
		var method: String = String(o[1])
		var args: Array = o[2] as Array if o.size()> 2 else []

		# basic safety: only rp_* methods are callable
		if not method.begins_with("rp_"):
			continue

		var root: Node = _resolve_child(child_id)
		if root == null:
			continue
		if root.has_method(method):
			# Use deferred call to avoid re-entrancy during network pump.
			root.callv.bind(method, args).call_deferred()
			#root.call_deferred(method, args)


func apply_despawns(ids: Array) -> void:
	for cid in ids:
		var child_id: int = int(cid)
		var n: Node = _dyn_nodes.get(child_id, null)
		_dyn_info.erase(child_id)
		if n:
			_dyn_nodes.erase(child_id)
			n.queue_free()


# --- Server-side marking & collection ----------------------------------------


func mark_child_prop(child_id: int, field_id: int, value: Variant, only_if_changed: bool = true) -> void:
	var cpid: int = ((child_id & 0xFFFF) << 16) | (field_id & 0xFFFF)
	synchronizer.mark_dirty_by_id(cpid, value, only_if_changed)


func mark_by_node(node: Node, field_id: int, value: Variant, only_if_changed: bool = true) -> void:
	var cid: int = child_id_of_node(node)
	if cid >= 0:
		mark_child_prop(cid, field_id, value, only_if_changed)


func queue_spawn(child_id: int, scene_id: int) -> void:
	_dyn_spawns_queued.append([child_id, scene_id])
	_dyn_info[child_id] = scene_id


func queue_despawn(child_id: int) -> void:
	_dyn_despawns_queued.append(child_id)
	_dyn_info.erase(child_id)


func queue_op(child_id: int, method: String, args: Array = []) -> void:
	_ops_named_queued.append([child_id, method, args])


func queue_op_by_node(node: Node, method: String, args: Array = []) -> void:
	var cid: int = child_id_of_node(node)
	if cid >= 0:
		queue_op(cid, method, args)


func collect_container_outgoing_and_clear() -> Dictionary:
	# Called by the server manager each tick.
	var pairs: Array = synchronizer.collect_dirty_pairs()    # [[cpid:int, value], ...]
	var spawns: Array = _dyn_spawns_queued.duplicate()
	var despawns: Array = _dyn_despawns_queued.duplicate()
	var ops_named: Array = _ops_named_queued.duplicate()

	_dyn_spawns_queued.clear()
	_dyn_despawns_queued.clear()
	_ops_named_queued.clear()

	return { "pairs": pairs, "spawns": spawns, "despawns": despawns, "ops_named": ops_named }


func alloc_dynamic_id() -> int:
	var cid: int = _next_dyn_id
	_next_dyn_id += 1
	if _next_dyn_id > 0xFFFF:
		_next_dyn_id = STATIC_MAX + 1
	return cid


# --- Baseline (server -> client) ---------------------------------------------


func set_baseline_ops(child_id: int, ops: Array) -> void:
	# ops = [[method:String, args:Array], ...], e.g., [["rp_pause", []]]
	_baseline_ops_by_child[child_id] = ops


func set_baseline_ops_by_node(node: Node, ops: Array) -> void:
	var cid: int = child_id_of_node(node)
	if cid >= 0:
		set_baseline_ops(cid, ops)


func clear_baseline_ops(child_id: int) -> void:
	_baseline_ops_by_child.erase(child_id)


func build_bootstrap_ops_named() -> Array:
	# Turn per-child lists into [[child_id, method, args], ...]
	var out: Array = []
	for child_id in _baseline_ops_by_child.keys():
		var ls: Array = _baseline_ops_by_child[child_id]
		for i in range(ls.size()):
			var e: Array = ls[i]
			if e.size() == 0:
				continue
			var method: String = String(e[0])
			var args: Array = e[1] as Array if e.size() > 1 else []
			out.append([int(child_id), method, args])
	return out


func capture_bootstrap_block() -> Dictionary:
	# For a new client: dynamic spawns currently alive + optional *property* baseline + named ops baseline.
	# You can keep "pairs" empty if you rely entirely on named ops for baseline (rp_*).
	var spawns: Array = []
	for child_id in _dyn_info.keys():
		spawns.append([int(child_id), int(_dyn_info[child_id])])

	var pairs: Array = synchronizer.capture_baseline()    # keep if you mix both models
	var ops_named: Array = build_bootstrap_ops_named()

	return { "spawns": spawns, "pairs": pairs, "despawns": [], "ops_named": ops_named }


# --- Queries / resolve --------------------------------------------------------


func child_id_of_node(n: Node) -> int:
	var rel: NodePath = get_path_to(n)
	return _relpath_to_id.get(rel, -1)


func _resolve_child(child_id: int) -> Node:
	if child_id <= STATIC_MAX:
		var rel: NodePath = id_to_relpath.get(child_id, NodePath())
		if rel.is_empty():
			return null
		var cached: Node = _node_cache.get(rel, null)
		if cached != null and is_instance_valid(cached):
			return cached
		var n: Node = get_node_or_null(rel)
		if n != null:
			_node_cache[rel] = n
		return n
	else:
		return _dyn_nodes.get(child_id, null)


func _resolve_under(root: Node, rel: NodePath) -> Node:
	return root if rel.is_empty() else root.get_node_or_null(rel)


func _tag_descendants(root: Node) -> void:
	const META := &"rp_container"
	for c in root.get_children():
		c.set_meta(META, self)
		_tag_descendants(c)
