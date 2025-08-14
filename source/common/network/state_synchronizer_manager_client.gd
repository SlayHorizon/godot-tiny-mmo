class_name StateSynchronizerManagerClient
extends Node
## Client-side manager: receives/decodes messages and applies them to local entities.

@export var server_peer_id: int = 1   # adjust to your topology

var entities: Dictionary[int, StateSynchronizer] = {}   # eid -> StateSynchronizer
var _pending_baseline: Dictionary[int, Array] = {}      # eid -> pairs
var _pending_deltas: Dictionary[int, Array] = {}        # eid -> Array of pairs arrays


func add_entity(eid: int, sync: StateSynchronizer) -> void:
	assert(sync != null, "StateSynchronizer must not be null.")
	entities[eid] = sync

	# Drain pending
	if _pending_baseline.has(eid):
		sync.apply_baseline(_pending_baseline[eid])
		_pending_baseline.erase(eid)

	if _pending_deltas.has(eid):
		var q: Array = _pending_deltas[eid]
		for i in range(q.size()):
			var pairs: Array = q[i]
			sync.apply_delta(pairs)
		_pending_deltas.erase(eid)


func remove_entity(eid: int) -> void:
	entities.erase(eid)
	_pending_baseline.erase(eid)
	_pending_deltas.erase(eid)


# --- Handlers from server -----------------------------------------------------


@rpc("authority", "reliable")
func on_bootstrap(payload: PackedByteArray) -> void:
	var msg: Dictionary = WireCodec.decode_bootstrap(payload)
	
	var updates: Array = msg.get("map_updates", [])
	if updates.size() > 0:
		PathRegistry.apply_map_updates(updates)

	var objects: Array = msg.get("objects", [])
	for i in range(objects.size()):
		var obj: Dictionary = objects[i]
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

	for i in range(blocks.size()):
		var blk: Dictionary = blocks[i]
		var eid: int = int(blk.get("eid", -1))
		var pairs: Array = blk.get("pairs", [])

		var syn: StateSynchronizer = entities.get(eid, null)
		if syn == null:
			var q: Array = _pending_deltas.get(eid, [])
			q.append(pairs)
			_pending_deltas[eid] = q
		else:
			syn.apply_delta(pairs)


# --- Client -> Server (optional deltas) --------------------------------------


func send_my_delta(eid: int, pairs: Array) -> void:
	if pairs.is_empty():
		return
	var blocks: Array = [ { "eid": eid, "pairs": pairs } ]
	var bytes: PackedByteArray = WireCodec.encode_delta(blocks)
	# Call server manager
	on_client_delta.rpc_id(server_peer_id, bytes)


@rpc("any_peer", "reliable")
func on_client_delta(bytes: PackedByteArray) -> void:
	pass


var containers: Dictionary[int, ReplicatedPropsContainer] = {}  # eid -> container
var _pending_cont_bootstrap: Array = []                         # bytes à rejouer si container pas encore add

func add_container(eid: int, container: ReplicatedPropsContainer) -> void:
	containers[eid] = container

@rpc("authority", "reliable")
func on_props_bootstrap(bytes: PackedByteArray) -> void:
	var msg: Dictionary = WireCodec.decode_container_block_named(bytes)
	
	var eid: int = int(msg.get("eid", -1))
	var cont: ReplicatedPropsContainer = containers.get(eid, null)
	if cont == null:
		_pending_cont_bootstrap.append(bytes)
		return
	cont.apply_spawns(msg.get("spawns", []))
	cont.apply_ops_named(msg.get("ops_named", []))   # IMPORTANT
	cont.apply_pairs(msg.get("pairs", []))
	cont.apply_despawns(msg.get("despawns", []))


@rpc("authority", "reliable")
func on_props_delta(bytes: PackedByteArray) -> void:
	var msg: Dictionary = WireCodec.decode_container_block_named(bytes)
	
	var eid: int = int(msg.get("eid", -1))
	
	var cont: ReplicatedPropsContainer = containers.get(eid, null)
	if cont == null:
		_pending_cont_bootstrap.append(bytes)
		return
	cont.apply_spawns(msg.get("spawns", []))
	cont.apply_ops_named(msg.get("ops_named", []))   # IMPORTANT
	cont.apply_pairs(msg.get("pairs", []))
	cont.apply_despawns(msg.get("despawns", []))
