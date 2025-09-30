@tool
class_name ReplicatedPropsContainer
extends Node2D
#Deterministic baked IDs → zero bootstrap for statics (no “200 jars” payload).
#Simple lookups (child index/id maps), cheap wire format (CPID 16/16).
#Clean split cold props (container) vs hot actors (StateSynchronizer).
#The tradeoffs are acceptable:
#Props must be direct children.
#Reordering children in the editor changes IDs unless we re-bake.

## Compact container for “cold” scene props (static & dynamic), independent from StateSynchronizer.
## Provides:
##  - Server: mark props (cpid->value), queue spawns/despawns/ops, capture bootstrap.
##  - Client: apply spawns, pairs, and rp_* ops.
##  - Minimal structures, hot-path cache per CPID, readable code.

## static ids in [0..STATIC_MAX], dynamic start above
const STATIC_MAX: int = 32767

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

@export_tool_button("Bake") var callback: Callable = _bake_static_map

@export var id_to_node: Dictionary[int, Node]
@export var node_to_id: Dictionary[Node, int]

var next_dynamic_prop_id: int = STATIC_MAX + 1
var dynamic_nodes: Dictionary[int, Node]

# --- Outgoing queues (server tick) -------------------------------------------

## [[child_id, scene_id], ...]
var _dyn_spawns_queued: Array
## [child_id, ...]
var _dyn_despawns_queued: Array
## [[child_id, StringName, args:Array], ...]
var _ops_named_queued: Array

# --- Props state & coalesced dirty (server) ----------------------------------

var _state_by_cpid: Dictionary[int, Variant] = {}   # cpid -> last value
var _dirty_pairs: Dictionary[int, Variant] = {}     # cpid -> pending value

# Optional: baseline “ops” per child (scene-owned state for newcomers).
var _baseline_ops_by_child: Dictionary[int, Array] = {}  # child_id -> [[method:StringName, args:Array], ...]

var _cpid_cache: Dictionary[int, PropertyCache]
var _pending_by_cpid: Dictionary[int, Variant]

func _ready() -> void:
	if Engine.is_editor_hint() and id_to_node.is_empty():
		_bake_static_map()


## Bake (editor): all immediate children become "static props"
func _bake_static_map() -> void:
	id_to_node.clear()
	node_to_id.clear()
	var next_id: int = 0
	for node: Node in get_children():
		id_to_node[next_id] = node
		node_to_id[node] = next_id
		next_id += 1


## Client side:
## spawns: [[child_id, scene_id], ...]
func apply_spawns(spawns: Array) -> void:
	for to_spawn: Array in spawns:
		if to_spawn.size() < 2:
			continue
		var child_id: int = to_spawn[0]
		var scene_id: int = to_spawn[1]

		# Already present? (e.g., replay)
		if _resolve_child(child_id) != null:
			continue

		var packed_scene: PackedScene = ContentRegistryHub.load_by_id(&"scenes", scene_id)
		if not packed_scene:
			continue

		var instance: Node = packed_scene.instantiate()
		dynamic_nodes[child_id] = instance
		instance.set_meta(&"rp_container", self)
		add_child(instance)
		
	_flush_pending_pairs_for_spawned(spawns)


func _flush_pending_pairs_for_spawned(spawns: Array) -> void:
	for to_spawn in spawns:
		if to_spawn.size() < 2: continue
		var child_id: int = to_spawn[0]
		var child: Node = _resolve_child(child_id)
		if child == null: continue
		# Try all CPIDs for this child
		for cpid in _pending_by_cpid.keys():
			if cpid_child(cpid) != child_id: continue
			var fid := cpid_field(cpid)
			var pc := PropertyCache.ensure_cache_for(fid, child, _cpid_cache, cpid)
			if pc != null and pc.apply_or_try_resolve(child, _pending_by_cpid[cpid]):
				_pending_by_cpid.erase(cpid)


## pairs: [[cpid, value], ...]
func apply_pairs(pairs: Array) -> void:
	for pair: Array in pairs:
		if pair.size() < 2:
			continue
		
		# Potential confusion here:
		# cpid is at the same time the node ID and the field/property ID
		var cpid: int = pair[0]
		var value: Variant = pair[1]

		var child_id: int = cpid_child(cpid)
		var fid: int = cpid_field(cpid)
		var child: Node = _resolve_child(child_id)
		if not child:
			_pending_by_cpid[cpid] = value
			continue
		
		var child_property_cache: PropertyCache = PropertyCache.ensure_cache_for(
			fid,
			child,
			_cpid_cache,
			cpid
		)

		if child_property_cache == null or not child_property_cache.apply_or_try_resolve(child, value):
			_pending_by_cpid[cpid] = value


## [[child_id, method, args], ...] ; only rp_* are executed (client-visual).
func apply_ops_named(ops_named: Array) -> void:
	for ops: Array in ops_named:
		if ops.size() < 2:
			continue
		var method_str: String = ops[1]
		if not method_str.begins_with("rp_"):
			continue
		var child_id: int = ops[0]
		var args: Array = ops[2] if ops.size() > 2 else []

		var root: Node = _resolve_child(child_id)
		if root == null:
			continue
		if root.has_method(method_str):
			# Defer to next idle frame to avoid reentrancy during net pump.
			Callable(root, method_str).bindv(args).call_deferred()


func apply_despawns(ids: Array) -> void:
	for cid: int in ids:
		var child_id: int = cid
		var node: Node = dynamic_nodes.get(child_id, null)
		if node:
			dynamic_nodes.erase(child_id)
			node.queue_free()


# --- Server-side marking & collection
func mark_child_prop(child_id: int, field_id: int, value: Variant, only_if_changed: bool = true) -> void:
	var cpid: int = make_cpid(child_id, field_id)
	if only_if_changed:
		var prev: Variant = _state_by_cpid.get(cpid, null)
		if prev != null and SyncUtils.roughly_equal(prev, value):
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
	var cid: int = next_dynamic_prop_id
	next_dynamic_prop_id += 1
	if next_dynamic_prop_id > 0xFFFF:
		next_dynamic_prop_id = STATIC_MAX + 1
	return cid


# --- Baseline (server -> client)

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
	# Client apply order must be: spawns → ops_named → pairs → despawns
	var spawns: Array = []
	for child_id: int in dynamic_nodes:
		var n: Node = dynamic_nodes[child_id]
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


# --- Resolve / utility
func child_id_of_node(node: Node) -> int:
	return node_to_id.get(node, -1)


func _resolve_child(child_id: int) -> Node:
	if child_id <= STATIC_MAX:
		return id_to_node.get(child_id, null)
	else:
		return dynamic_nodes.get(child_id, null)


func _resolve_under(root: Node, rel: NodePath) -> Node:
	return root if rel.is_empty() else root.get_node_or_null(rel)
