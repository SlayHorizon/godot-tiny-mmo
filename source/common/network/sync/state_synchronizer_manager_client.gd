class_name StateSynchronizerManagerClient
extends Node
## Client-side manager: receives/decodes messages and applies them to local entities & props.

@export var server_peer_id: int = 1   # adjust to your topology

var entities: Dictionary[int, StateSynchronizer] = {}   # eid -> StateSynchronizer
var _pending_baseline: Dictionary[int, Array] = {}      # eid -> pairs
var _pending_deltas: Dictionary[int, Array] = {}        # eid -> Array of pairs arrays

var containers: Dictionary[int, ReplicatedPropsContainer] = {}  # cid -> container
var _pending_prop_blocks: Array = []   # store raw bytes until container is registered


func add_entity(eid: int, sync: StateSynchronizer) -> void:
	assert(sync != null, "StateSynchronizer must not be null.")
	entities[eid] = sync

	# Drain pending baseline/deltas for this entity.
	var base: Array = _pending_baseline.get(eid, [])
	if base.size() > 0:
		sync.apply_baseline(base)
		_pending_baseline.erase(eid)

	var q: Array = _pending_deltas.get(eid, [])
	if q.size() > 0:
		for pairs: Array in q:
			sync.apply_delta(pairs)
		_pending_deltas.erase(eid)


func remove_entity(eid: int) -> void:
	entities.erase(eid)
	_pending_baseline.erase(eid)
	_pending_deltas.erase(eid)


func add_container(cid: int, container: ReplicatedPropsContainer) -> void:
	assert(container != null)
	containers[cid] = container

	# Drain any pending prop blocks (bootstrap/delta) targeting this container.
	if _pending_prop_blocks.is_empty():
		return

	var remain: Array = []
	for bb: PackedByteArray in _pending_prop_blocks:
		var msg: Dictionary = WireCodec.peek_container_block_named(bb)  # assume you have a cheap peek; else decode fully
		var eid: int = int(msg.get("eid", -1))
		if eid == cid:
			# apply now with correct order: spawns → ops → pairs → despawns
			var full: Dictionary = WireCodec.decode_container_block_named(bb)
			var cont: ReplicatedPropsContainer = containers.get(cid, null)
			if cont != null:
				cont.apply_spawns(full.get("spawns", []))
				cont.apply_ops_named(full.get("ops_named", []))
				cont.apply_pairs(full.get("pairs", []))
				cont.apply_despawns(full.get("despawns", []))
		else:
			remain.append(bb)

	_pending_prop_blocks = remain


func remove_container(cid: int) -> void:
	containers.erase(cid)


# --- Entities (hot) -----------------------------------------------------------

@rpc("authority", "reliable")
func on_bootstrap(payload: PackedByteArray) -> void:
	var msg: Dictionary = WireCodec.decode_bootstrap(payload)

	# Updated already applied inside codec
	#var updates: Array = msg.get("map_updates", [])
	
	#if updates.size() > 0:
		#PathRegistry.apply_map_updates(updates)

	var objects: Array = msg.get("objects", [])
	for obj_any in objects:
		var obj: Dictionary = obj_any
		var eid: int = int(obj.get("eid", -1))
		var pairs: Array = obj.get("pairs", [])
		var syn: StateSynchronizer = entities.get(eid, null)
		if syn == null:
			_pending_baseline[eid] = pairs
		else:
			syn.apply_baseline(pairs)


@rpc("authority", "reliable")
func on_state_delta(bytes: PackedByteArray) -> void:
	var blocks: Array = WireCodec.decode_delta(bytes)
	for blk_any in blocks:
		var blk: Dictionary = blk_any
		var eid: int = int(blk.get("eid", -1))
		var pairs: Array = blk.get("pairs", [])
		var syn: StateSynchronizer = entities.get(eid, null)
		if syn == null:
			var q: Array = _pending_deltas.get(eid, [])
			q.append(pairs)
			_pending_deltas[eid] = q
		else:
			syn.apply_delta(pairs)


func send_my_delta(eid: int, pairs: Array) -> void:
	if pairs.is_empty():
		return
	var blocks: Array = [ { "eid": eid, "pairs": pairs } ]
	var bytes: PackedByteArray = WireCodec.encode_delta(blocks)
	on_client_delta.rpc_id(server_peer_id, bytes)


@rpc("any_peer", "reliable")
func on_client_delta(_bytes: PackedByteArray) -> void:
	pass


# --- Props (cold) -------------------------------------------------------------

@rpc("authority", "reliable")
func on_props_bootstrap(bytes: PackedByteArray) -> void:
	# We may receive multiple container blocks; apply order is inside each block.
	var msg: Dictionary = WireCodec.decode_container_block_named(bytes)
	var cid: int = int(msg.get("eid", -1))
	var cont: ReplicatedPropsContainer = containers.get(cid, null)
	if cont == null:
		_pending_prop_blocks.append(bytes)
		return

	# Order matters: spawns → ops → pairs → despawns
	cont.apply_spawns(msg.get("spawns", []))
	cont.apply_ops_named(msg.get("ops_named", []))
	cont.apply_pairs(msg.get("pairs", []))
	cont.apply_despawns(msg.get("despawns", []))


@rpc("authority", "reliable")
func on_props_delta(bytes: PackedByteArray) -> void:
	var msg: Dictionary = WireCodec.decode_container_block_named(bytes)
	var cid: int = int(msg.get("eid", -1))
	var cont: ReplicatedPropsContainer = containers.get(cid, null)
	if cont == null:
		_pending_prop_blocks.append(bytes)
		return

	# Order matters: spawns → ops → pairs → despawns
	cont.apply_spawns(msg.get("spawns", []))
	cont.apply_ops_named(msg.get("ops_named", []))
	cont.apply_pairs(msg.get("pairs", []))
	cont.apply_despawns(msg.get("despawns", []))
