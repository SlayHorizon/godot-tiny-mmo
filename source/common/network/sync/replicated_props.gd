@tool
class_name ReplicatedPropsContainer
extends Node
## Compact container for “cold” scene props (static & dynamic), independent from StateSynchronizer.
## Provides:
##  - Server: mark props (cpid->value), queue spawns/despawns/ops, capture bootstrap.
##  - Client: apply spawns, pairs, and rp_* ops.
##  - Minimal structures, hot-path cache per CPID, readable code.

# --- CPID helpers (16 bits child / 16 bits field) 6-

const CPID_CHILD_BITS := 16
const CPID_FIELD_BITS := 16
const CPID_FIELD_MASK := 0xFFFF
const CPID_CHILD_MASK := 0xFFFF

static func make_cpid(child_id: int, field_id: int) -> int:
	assert(child_id >= 0 and child_id <= CPID_CHILD_MASK)
	assert(field_id >= 0 and field_id <= CPID_FIELD_MASK)
	return ((child_id & CPID_CHILD_MASK) << CPID_FIELD_BITS) | (field_id & CPID_FIELD_MASK)

static func cpid_child(cpid: int) -> int:
	return (cpid >> CPID_FIELD_BITS) & CPID_CHILD_MASK

static func cpid_field(cpid: int) -> int:
	return cpid & CPID_FIELD_MASK


# --- Tolerant compare for floats/vec2 (reduce noise) -------------------------

@export var enable_tolerant_compare: bool = true
@export var eps_f32: float = 0.001
@export var eps_vec2_len2: float = 0.0001


# --- Static mapping (baked once) ---------------------------------------------

@export_tool_button("Bake") var callback: Callable = _bake_static_map

## child_id -> relative NodePath (from this container)
@export var id_to_relpath: Dictionary[int, NodePath] = {}

## reverse: relpath -> child_id (rebuilt at load/bake)
@export var _relpath_to_id: Dictionary[NodePath, int] = {}

## static ids in [0..STATIC_MAX], dynamic start above
const STATIC_MAX: int = 32767


# --- Dynamic registry (lean) --------------------------------------------------

var _dyn_nodes: Dictionary[int, Node] = {}     # child_id -> Node
var _next_dyn_id: int = STATIC_MAX + 1


# --- Outgoing queues (server tick) -------------------------------------------

var _dyn_spawns_queued: Array = []             # [[child_id, scene_id], ...]
var _dyn_despawns_queued: Array = []           # [child_id, ...]
var _ops_named_queued: Array = []              # [[child_id, StringName, args:Array], ...]


# --- Props state & coalesced dirty (server) ----------------------------------

var _state_by_cpid: Dictionary[int, Variant] = {}   # cpid -> last value
var _dirty_pairs: Dictionary[int, Variant] = {}     # cpid -> pending value

# Optional: baseline “ops” per child (scene-owned state for newcomers).
var _baseline_ops_by_child: Dictionary[int, Array] = {}  # child_id -> [[method:StringName, args:Array], ...]


# --- Per-CPID target cache (client hot path) ---------------------------------

class CpidCache:
	var child_id: int
	var node_rel: NodePath      # relative node path under the child root
	var prop_path: NodePath     # property segment (":position", "Sprite2D:scale", ...)
	var root: Node = null
	var target: Node = null

	func apply_or_try_resolve(container: ReplicatedPropsContainer, value: Variant) -> bool:
		if root == null or not is_instance_valid(root):
			root = container._resolve_child(child_id)
			if root == null:
				return false
			target = null
		if target == null or not is_instance_valid(target):
			target = container._resolve_under(root, node_rel)
			if target == null:
				return false
		target.set_indexed(prop_path, value)
		return true

var _cpid_cache: Dictionary[int, CpidCache] = {}


# --- Lifecycle ----------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint() and id_to_relpath.is_empty():
		_bake_static_map()
		return
	_relpath_to_id.clear()
	for id: int in id_to_relpath:
		_relpath_to_id[id_to_relpath[id]] = id
	_tag_descendants(self)


# --- Bake (editor): all immediate children become “static props” -------------

func _bake_static_map() -> void:
	id_to_relpath.clear()
	_relpath_to_id.clear()
	var next_id: int = 0
	for n: Node in get_children():
		var rel: NodePath = get_path_to(n)
		id_to_relpath[next_id] = rel
		_relpath_to_id[rel] = next_id
		next_id += 1
	_tag_descendants(self)


# --- Client-side apply --------------------------------------------------------

func apply_spawns(spawns: Array) -> void:
	# spawns: [[child_id, scene_id], ...]
	for s: Array in spawns:
		if s.size() < 2:
			continue
		var child_id: int = s[0]
		var scene_id: int = s[1]

		# Already present? (e.g., replay)
		if _resolve_child(child_id) != null:
			continue

		var scene_path: String = SceneRegistry.path_of(scene_id)
		var ps: PackedScene = load(scene_path)
		if ps == null:
			continue

		var inst: Node = ps.instantiate()
		# Store scene_id on the node to rebuild bootstrap later if needed.
		inst.set_meta(&"scene_id", scene_id)
		add_child(inst)
		_dyn_nodes[child_id] = inst
		_tag_descendants(inst)


func apply_pairs(pairs: Array) -> void:
	# pairs: [[cpid, value], ...]
	for p: Array in pairs:
		if p.size() < 2:
			continue
		var cpid: int = p[0]
		var value: Variant = p[1]

		var cc: CpidCache = _cpid_cache.get(cpid, null)
		if cc == null:
			var child_id: int = cpid_child(cpid)
			var fid: int = cpid_field(cpid)
			var rel_np: NodePath = PathRegistry.nodepath_of(fid)
			if rel_np.is_empty():
				continue
			cc = CpidCache.new()
			cc.child_id = child_id
			cc.node_rel = TinyNodePath.get_path_to_node(rel_np)
			cc.prop_path = TinyNodePath.get_path_to_property(rel_np)
			_cpid_cache[cpid] = cc

		if not cc.apply_or_try_resolve(self, value):
			# simple: skip if child not ready yet (orders generally ensure readiness)
			# (si tu veux, on peut bufferiser ici)
			pass


func apply_ops_named(ops_named: Array) -> void:
	# [[child_id, method, args], ...] ; only rp_* are executed (client-visual).
	for o: Array in ops_named:
		if o.size() < 2:
			continue
		var method_str: String = String(o[1])
		if not method_str.begins_with("rp_"):
			continue
		var child_id: int = o[0]
		var args: Array = o[2] if o.size() > 2 else []

		var root: Node = _resolve_child(child_id)
		if root == null:
			continue
		if root.has_method(method_str):
			# Defer to next idle frame to avoid reentrancy during net pump.
			Callable(root, method_str).bindv(args).call_deferred()


func apply_despawns(ids: Array) -> void:
	for cid in ids:
		var child_id: int = int(cid)
		var n: Node = _dyn_nodes.get(child_id, null)
		if n:
			_dyn_nodes.erase(child_id)
			n.queue_free()


# --- Server-side marking & collection ----------------------------------------

func mark_child_prop(child_id: int, field_id: int, value: Variant, only_if_changed: bool = true) -> void:
	var cpid: int = make_cpid(child_id, field_id)
	if only_if_changed:
		var prev: Variant = _state_by_cpid.get(cpid, null)
		if prev != null and _roughly_equal(field_id, prev, value):
			return
	_state_by_cpid[cpid] = value
	_dirty_pairs[cpid] = value


func mark_by_node(node: Node, field_id: int, value: Variant, only_if_changed: bool = true) -> void:
	var cid: int = child_id_of_node(node)
	if cid >= 0:
		mark_child_prop(cid, field_id, value, only_if_changed)


func queue_spawn(child_id: int, scene_id: int) -> void:
	_dyn_spawns_queued.append([child_id, scene_id])


func queue_despawn(child_id: int) -> void:
	_dyn_despawns_queued.append(child_id)


func queue_op(child_id: int, method: String, args: Array = []) -> void:
	_ops_named_queued.append([child_id, StringName(method), args])


func queue_op_by_node(node: Node, method: String, args: Array = []) -> void:
	var cid: int = child_id_of_node(node)
	if cid >= 0:
		queue_op(cid, method, args)


func collect_container_outgoing_and_clear() -> Dictionary:
	# Called by the server manager each tick.
	var spawns: Array = _dyn_spawns_queued.duplicate()
	var despawns: Array = _dyn_despawns_queued.duplicate()
	var ops_named: Array = _ops_named_queued.duplicate()

	var pairs: Array = []
	for cpid: int in _dirty_pairs:
		pairs.append([cpid, _dirty_pairs[cpid]])
	_dirty_pairs.clear()

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
	# ops = [[method:String|StringName, args:Array], ...]
	_baseline_ops_by_child[child_id] = ops


func set_baseline_ops_by_node(node: Node, ops: Array) -> void:
	var cid: int = child_id_of_node(node)
	if cid >= 0:
		set_baseline_ops(cid, ops)


func clear_baseline_ops(child_id: int) -> void:
	_baseline_ops_by_child.erase(child_id)


func build_bootstrap_ops_named() -> Array:
	var out: Array = []
	for child_id: int in _baseline_ops_by_child:
		var ls: Array = _baseline_ops_by_child[child_id]
		for e: Array in ls:
			if e.is_empty():
				continue
			var method: StringName = StringName(e[0])
			var args: Array = e[1] if e.size() > 1 else []
			out.append([child_id, method, args])
	return out


func capture_bootstrap_block() -> Dictionary:
	# New client should get:
	# - current dynamics (spawns with scene_id from node.meta),
	# - optional pairs baseline,
	# - named ops baseline (scene-owned state like rp_pause).
	var spawns: Array = []
	for child_id: int in _dyn_nodes:
		var n: Node = _dyn_nodes[child_id]
		if n == null or not is_instance_valid(n):
			continue
		var scene_id: int = int(n.get_meta(&"scene_id", -1))
		if scene_id >= 0:
			spawns.append([child_id, scene_id])

	var pairs: Array = []
	for cpid: int in _state_by_cpid:
		pairs.append([cpid, _state_by_cpid[cpid]])

	var ops_named: Array = build_bootstrap_ops_named()

	return { "spawns": spawns, "pairs": pairs, "despawns": [], "ops_named": ops_named }


# --- Resolve / utility --------------------------------------------------------

func child_id_of_node(n: Node) -> int:
	var rel: NodePath = get_path_to(n)
	return _relpath_to_id.get(rel, -1)


func _resolve_child(child_id: int) -> Node:
	if child_id <= STATIC_MAX:
		var rel: NodePath = id_to_relpath.get(child_id, NodePath())
		return null if rel.is_empty() else get_node_or_null(rel)
	else:
		return _dyn_nodes.get(child_id, null)


func _resolve_under(root: Node, rel: NodePath) -> Node:
	return root if rel.is_empty() else root.get_node_or_null(rel)


func _tag_descendants(root: Node) -> void:
	const META := &"rp_container"
	for c: Node in root.get_children():
		c.set_meta(META, self)
		_tag_descendants(c)


# --- Compare helper -----------------------------------------------------------

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
