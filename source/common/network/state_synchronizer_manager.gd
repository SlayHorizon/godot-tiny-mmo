class_name StateSynchronizerManagerServer
extends Node
## Per-instance manager: owns the set of networked entities, batches deltas, and encodes/decodes payloads.
## Server side:
##  - register peers/entities
##  - send_bootstrap(peer)
##  - send_deltas_tick() @ ~20 Hz
## Client side:
##  - on_bootstrap(bytes) -> apply mappings + baselines
##  - on_state_delta(bytes) -> apply deltas

@export var send_rate_hz_entities: int = 20
@export var send_rate_hz_props: int = 10
@export var enable_process_tick: bool = true

var _accum_ent := 0.0
var _accum_props := 0.0

class PeerState:
	var known_version: int = 0
	# Future: AOI state, throttling, last_send_ms, etc.

var entities: Dictionary[int, StateSynchronizer] = {}   # eid -> StateSynchronizer
var peers: Dictionary[int, PeerState] = {}              # peer_id -> PeerState

var _accum_time: float = 0.0


func _ready() -> void:
	set_process(enable_process_tick)


#func _process(delta: float) -> void:
	#if not enable_process_tick:
		#return
	#_accum_time += delta
	#var interval: float = 1.0 / float(send_rate_hz)
	#if _accum_time >= interval:
		## keep residual to minimize drift
		#_accum_time -= interval
		#printraw("send deltatick//")
		#send_deltas_tick()
func _process(delta: float) -> void:
	if not enable_process_tick:
		return
	_accum_ent += delta
	_accum_props += delta

	var eint := 1.0 / float(send_rate_hz_entities)
	var pint := 1.0 / float(send_rate_hz_props)

	if _accum_ent >= eint:
		_accum_ent = fmod(_accum_ent, eint)
		_send_entity_deltas_one_shot()

	if _accum_props >= pint:
		_accum_props = fmod(_accum_props, pint)
		_send_container_deltas_one_shot()


func _send_entity_deltas_one_shot() -> void:
	if peers.is_empty():
		return
	var changed_pairs: Dictionary[int, Array] = {}
	for eid_any in entities.keys():
		var eid: int = int(eid_any)
		var syn: StateSynchronizer = entities[eid]
		var pairs: Array = syn.collect_dirty_pairs()
		if pairs.size() > 0:
			changed_pairs[eid] = pairs
	if changed_pairs.is_empty():
		return
	var block_bytes_by_eid: Dictionary[int, PackedByteArray] = {}
	for eid2 in changed_pairs.keys():
		block_bytes_by_eid[int(eid2)] = WireCodec.encode_entity_block(int(eid2), changed_pairs[eid2])
	var peer_ids: PackedInt32Array = peers.keys()
	for pid in peer_ids:
		var peer_id := int(pid)
		var blocks_for_peer: Array = []
		for eid3 in _aoi_entities_for(peer_id):
			var e := int(eid3)
			if e == peer_id:
				continue
			var bb: PackedByteArray = block_bytes_by_eid.get(e, PackedByteArray())
			if bb.size() > 0:
				blocks_for_peer.append(bb)
		if blocks_for_peer.size() > 0:
			on_state_delta.rpc_id(peer_id, WireCodec.assemble_delta_from_blocks(blocks_for_peer))


func _send_container_deltas_one_shot() -> void:
	if peers.is_empty():
		return
	var cont_blocks: Array = []
	for ceid in containers.keys():
		var cont: ReplicatedPropsContainer = containers[ceid]
		var out := cont.collect_container_outgoing_and_clear()
		var spawns: Array = out.get("spawns", [])
		var pairs: Array = out.get("pairs", [])
		var despawns: Array = out.get("despawns", [])
		var ops_named: Array = out.get("ops_named", [])
		if spawns.is_empty() and pairs.is_empty() and despawns.is_empty() and ops_named.is_empty():
			continue
		cont_blocks.append(WireCodec.encode_container_block_named(int(ceid), spawns, pairs, despawns, ops_named))
	if cont_blocks.size() == 0:
		return
	for peer_id in peers.keys():
		for bb in cont_blocks:
			on_props_delta.rpc_id(int(peer_id), bb)

# --- Entity & peer management -------------------------------------------------


func add_entity(eid: int, sync: StateSynchronizer) -> void:
	assert(sync != null, "StateSynchronizer must not be null.")
	entities[eid] = sync


func remove_entity(eid: int) -> void:
	entities.erase(eid)


func register_peer(peer_id: int) -> void:
	if peers.has(peer_id):
		return
	var ps: PeerState = PeerState.new()
	ps.known_version = 0
	peers[peer_id] = ps
	send_bootstrap(peer_id)


func unregister_peer(peer_id: int) -> void:
	peers.erase(peer_id)


# --- Bootstrap (server -> client) --------------------------------------------


func send_bootstrap(peer_id: int) -> void:
	var updates: Array = _calc_map_updates_for_peer(peer_id)
	var objects: Array = []

	for eid: int in entities.keys():
		var syn: StateSynchronizer = entities[eid]
		var pairs: Array = syn.capture_baseline()
		if pairs.size():
			objects.append({ "eid": int(eid), "pairs": pairs })
	
	var payload: PackedByteArray = WireCodec.encode_bootstrap(updates, objects)
	on_bootstrap.rpc_id(peer_id, payload)

	# Send props baselines from container.
	for ceid in containers.keys():
		var cont: ReplicatedPropsContainer = containers[ceid]
		var blk: Dictionary = cont.capture_bootstrap_block()
		var bytes: PackedByteArray = WireCodec.encode_container_block_named(
			int(ceid),
			blk.get("spawns", []),
			blk.get("pairs", []),
			blk.get("despawns", []),
			blk.get("ops_named", [])
		)
		on_props_bootstrap.rpc_id(peer_id, bytes)


func _calc_map_updates_for_peer(peer_id: int) -> Array:
	var ps: PeerState = peers.get(peer_id, null)
	if ps == null:
		return []
	var current_ver: int = PathRegistry.version()
	if ps.known_version != current_ver:
		ps.known_version = current_ver
		return PathRegistry.get_full_map_updates()
	return []


# --- Delta tick (server -> client) -------------------------------------------


func send_deltas_tick() -> void:
	if peers.is_empty():
		return

	# 1) collect dirty once
	var changed_pairs: Dictionary[int, Array] = {}
	for eid_any in entities.keys():
		var eid: int = int(eid_any)
		var syn: StateSynchronizer = entities[eid]
		var pairs: Array = syn.collect_dirty_pairs()
		if pairs.size() > 0:
			changed_pairs[eid] = pairs
	if changed_pairs.is_empty():
		return

	# 2) pre-encode one block per entity
	var block_bytes_by_eid: Dictionary[int, PackedByteArray] = {}
	for eid2 in changed_pairs.keys():
		var pairs2: Array = changed_pairs[eid2]
		block_bytes_by_eid[int(eid2)] = WireCodec.encode_entity_block(int(eid2), pairs2)

	# 3) assemble per peer (skip self) — no re-encode
	var peer_ids: PackedInt32Array = peers.keys()
	for i in range(peer_ids.size()):
		var peer_id: int = int(peer_ids[i])
		var aoi_eids: Array = _aoi_entities_for(peer_id)

		var blocks_for_peer: Array = []
		for j in range(aoi_eids.size()):
			var eid3: int = int(aoi_eids[j])

			if eid3 == peer_id:
				continue

			var bb: PackedByteArray = block_bytes_by_eid.get(eid3, PackedByteArray())
			if bb.size() > 0:
				blocks_for_peer.append(bb)

		if blocks_for_peer.size() == 0:
			continue

		var bytes: PackedByteArray = WireCodec.assemble_delta_from_blocks(blocks_for_peer)
		on_state_delta.rpc_id(peer_id, bytes)
	
	
	var any_container_change := false
	var cont_blocks: Array = []
	for ceid in containers.keys():
		var cont: ReplicatedPropsContainer = containers[ceid]
		var out: Dictionary = cont.collect_container_outgoing_and_clear()
		var spawns: Array = out.get("spawns", [])
		var pairs: Array = out.get("pairs", [])
		var despawns: Array = out.get("despawns", [])
		var ops_named: Array = out.get("ops_named", [])
		if spawns.is_empty() and pairs.is_empty() and despawns.is_empty() and ops_named.is_empty():
			continue
		any_container_change = true
		cont_blocks.append(WireCodec.encode_container_block_named(int(ceid), spawns, pairs, despawns, ops_named))

	if any_container_change:
		#  noskip-self for containers
		for peer_id in peers.keys():
			for bb in cont_blocks:
				on_props_delta.rpc_id(int(peer_id), bb)


func _aoi_entities_for(peer_id: int) -> Array:
	# TODO: integrate AOI (grid/rooms). For now: include all.
	return entities.keys()


func send_correction_to_owner(eid: int, pairs: Array) -> void:
	# Ici ownership = eid == peer_id ; si tu ajoutes un owner map plus tard, remplace par la résolution correspondante.
	var owner_peer_id: int = eid
	if not peers.has(owner_peer_id):
		return
	var bb: PackedByteArray = WireCodec.encode_entity_block(eid, pairs)
	var bytes: PackedByteArray = WireCodec.assemble_delta_from_blocks([bb])
	on_state_delta.rpc_id(owner_peer_id, bytes)



# --- Client-side handlers (decode + apply) -----------------------------------


@rpc("authority", "reliable")
func on_bootstrap(payload: PackedByteArray) -> void:
	pass


@rpc("authority", "reliable")
func on_state_delta(bytes: PackedByteArray) -> void:
	pass


@rpc("any_peer", "reliable")
func on_client_delta(bytes: PackedByteArray) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	var blocks: Array = WireCodec.decode_delta(bytes)
	
	if blocks.is_empty():
		return

	var first: Dictionary = blocks[0]
	var eid: int = int(first.get("eid", sender))
	var pairs: Array = first.get("pairs", [])

	# Only the session that owns eid can push deltas for it
	if eid != sender:
		return
	
	# TODO: whitelist + sanity checks here
	var syn: StateSynchronizer = entities.get(eid, null)
	if syn != null and pairs.size() > 0:
		syn.apply_delta(pairs)
		syn.mark_many_by_id(pairs, false)


var containers: Dictionary[int, ReplicatedPropsContainer] = {}   # eid -> container

func add_container(eid: int, container: ReplicatedPropsContainer) -> void:
	assert(container != null)
	containers[eid] = container

func remove_container(eid: int) -> void:
	containers.erase(eid)


@rpc("authority", "reliable")
func on_props_bootstrap(_bytes: PackedByteArray) -> void:
	pass

@rpc("authority", "reliable")
func on_props_delta(_bytes: PackedByteArray) -> void:
	pass
