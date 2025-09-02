class_name StateSynchronizerManagerServer
extends Node
## Per-instance manager.
## - Entities (hot): own StateSynchronizer per EID, pre-encode per-entity blocks, per-peer assembly (skip-self).
## - Props (cold): own ReplicatedPropsContainer per CID (container id), broadcast or AOI later.
## - Sends PathRegistry map updates on bootstrap AND whenever the schema version changes.

@export var send_rate_hz_entities: int = 20
@export var send_rate_hz_props: int = 10
@export var enable_process_tick: bool = true
@export var owner_predict_suppress_ms: int = 120

var _accum_ent := 0.0
var _accum_props := 0.0

class PeerState:
	var known_version: int = 0
	# Future: AOI state, throttling, last_send_ms, etc.

var entities: Dictionary[int, StateSynchronizer] = {}   # eid -> StateSynchronizer
# owner -> fid -> { "t": ms, "v": value }
var _owner_recent: Dictionary[int, Dictionary] = {}
var peers: Dictionary[int, PeerState] = {}              # peer_id -> PeerState
var containers: Dictionary[int, ReplicatedPropsContainer] = {}  # cid -> container


func _ready() -> void:
	set_process(enable_process_tick)


func _process(delta: float) -> void:
	if not enable_process_tick:
		return
	_accum_ent += delta
	_accum_props += delta

	var eint: float = 1.0 / float(send_rate_hz_entities)
	var pint: float = 1.0 / float(send_rate_hz_props)

	if _accum_ent >= eint:
		_accum_ent = fmod(_accum_ent, eint)
		_send_entity_deltas_one_shot()

	if _accum_props >= pint:
		_accum_props = fmod(_accum_props, pint)
		_send_container_deltas_one_shot()


func _track_client_pairs(eid: int, pairs: Array) -> void:
	var now := Time.get_ticks_msec()
	var m: Dictionary = _owner_recent.get(eid, {})
	for p in pairs:
		if p.size() < 2:
			continue
		var fid: int = p[0]
		m[fid] = { "t": now, "v": p[1] }
	_owner_recent[eid] = m


# --- Entities (hot) -----------------------------------------------------------

func _send_entity_deltas_one_shot() -> void:
	if peers.is_empty():
		return

	# 0) push PathRegistry updates if schema changed
	_send_map_updates_if_needed_to_all()

	# 1) collect dirty once
	var changed_pairs: Dictionary[int, Array] = {}
	for eid: int in entities:
		var syn: StateSynchronizer = entities[eid]
		var pairs: Array = syn.collect_dirty_pairs()
		if pairs.size() > 0:
			changed_pairs[eid] = pairs
	if changed_pairs.is_empty():
		return

	# 2) pre-encode one block per entity (no re-encode later)
	var block_bytes_by_eid: Dictionary[int, PackedByteArray] = {}
	for eid2: int in changed_pairs:
		block_bytes_by_eid[eid2] = WireCodec.encode_entity_block(eid2, changed_pairs[eid2])

	# 3) assemble per peer (skip self)
	var now_ms: float = Time.get_ticks_msec()
	for peer_id: int in peers:
		var aoi_eids: Array = _aoi_entities_for(peer_id)
		var blocks_for_peer: Array = []
		
		for e_any in aoi_eids:
			var eid: int = int(e_any)
			
			var pairs: Array = changed_pairs.get(eid, [])
			if pairs.is_empty():
				continue
			
			if eid == peer_id:
				var filtered: Array = []
				for pair: Array in pairs:
					if pair.size() < 2:
						continue
					var fid: int = pair[0]
					var value: Variant = pair[1]
					if not _should_suppress_for_owner(peer_id, fid, value, now_ms):
						filtered.append(pair)
				if filtered.size() == 0:
					continue
				blocks_for_peer.append(WireCodec.encode_entity_block(eid, filtered))
			else:
				var bb: PackedByteArray = block_bytes_by_eid.get(eid, PackedByteArray())
				if bb.size() > 0:
					blocks_for_peer.append(bb)
				
		if blocks_for_peer.size() > 0:
			on_state_delta.rpc_id(peer_id, WireCodec.assemble_delta_from_blocks(blocks_for_peer))
	_prune_owner_recent(1000)


# --- Props (cold) -------------------------------------------------------------

func _send_container_deltas_one_shot() -> void:
	if peers.is_empty():
		return

	var cont_blocks: Array = []
	for cid: int in containers:
		var cont: ReplicatedPropsContainer = containers[cid]
		var out: Dictionary = cont.collect_container_outgoing_and_clear()
		var spawns: Array = out.get("spawns", [])
		var pairs: Array = out.get("pairs", [])
		var despawns: Array = out.get("despawns", [])
		var ops_named: Array = out.get("ops_named", [])
		if spawns.is_empty() and pairs.is_empty() and despawns.is_empty() and ops_named.is_empty():
			continue
		# Keep named ops ordering on client: spawns → ops → pairs → despawns
		cont_blocks.append(WireCodec.encode_container_block_named(cid, spawns, pairs, despawns, ops_named))

	if cont_blocks.is_empty():
		return

	# For now broadcast to all (AOI later)
	for peer_id: int in peers:
		for bb: PackedByteArray in cont_blocks:
			on_props_delta.rpc_id(peer_id, bb)


# --- Entity & peer management -------------------------------------------------

func add_entity(eid: int, sync: StateSynchronizer) -> void:
	assert(sync != null, "StateSynchronizer must not be null.")
	entities[eid] = sync


func remove_entity(eid: int) -> void:
	entities.erase(eid)


func add_container(cid: int, container: ReplicatedPropsContainer) -> void:
	assert(container != null)
	containers[cid] = container


func remove_container(cid: int) -> void:
	containers.erase(cid)


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
	# Send PathRegistry mapping first (if needed)
	var updates: Array = _calc_map_updates_for_peer(peer_id)

	# Entities baselines
	var objects: Array = []
	for eid: int in entities:
		var syn: StateSynchronizer = entities[eid]
		var pairs: Array = syn.capture_baseline()
		if pairs.size() > 0:
			objects.append({ "eid": eid, "pairs": pairs })

	var payload: PackedByteArray = WireCodec.encode_bootstrap(updates, objects)
	on_bootstrap.rpc_id(peer_id, payload)

	# Props baselines (containers)
	for cid: int in containers:
		var cont: ReplicatedPropsContainer = containers[cid]
		var blk: Dictionary = cont.capture_bootstrap_block()
		var bytes: PackedByteArray = WireCodec.encode_container_block_named(
			cid,
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


func _send_map_updates_if_needed_to_all() -> void:
	for peer_id: int in peers:
		var updates: Array = _calc_map_updates_for_peer(peer_id)
		if updates.is_empty():
			continue
		# Send an empty bootstrap containing only map updates.
		var payload: PackedByteArray = WireCodec.encode_bootstrap(updates, [])
		on_bootstrap.rpc_id(peer_id, payload)


# --- AOI hooks ----------------------------------------------------------------

func _aoi_entities_for(_peer_id: int) -> Array:
	# TODO: Replace with room/grid-based AOI.
	return entities.keys()


# --- Owner correction (server → owner only) ----------------------------------

func send_correction_to_owner(eid: int, pairs: Array) -> void:
	var owner_peer_id: int = eid  # Replace by real ownership map later.
	if not peers.has(owner_peer_id):
		return
	if pairs.is_empty():
		return
	var bb: PackedByteArray = WireCodec.encode_entity_block(eid, pairs)
	var bytes: PackedByteArray = WireCodec.assemble_delta_from_blocks([bb])
	on_state_delta.rpc_id(owner_peer_id, bytes)


# --- Client-side handlers mirrored for RPC presence ---------------------------

@rpc("authority", "reliable")
func on_bootstrap(_payload: PackedByteArray) -> void:
	pass


@rpc("authority", "reliable")
func on_state_delta(_bytes: PackedByteArray) -> void:
	pass


@rpc("any_peer", "reliable")
func on_client_delta(bytes: PackedByteArray) -> void:
	# Receive client-proposed deltas (owner-pushed) — keep strict.
	var sender: int = multiplayer.get_remote_sender_id()
	var blocks: Array = WireCodec.decode_delta(bytes)
	if blocks.is_empty():
		return

	var first: Dictionary = blocks[0]
	var eid: int = int(first.get("eid", sender))
	var pairs: Array = first.get("pairs", [])

	# Only the session that owns eid can push deltas for it.
	if eid != sender:
		return

	# TODO (important): validate pairs against a whitelist of writable fields.
	# For now, apply then re-mark to echo back in next tick (prediction-friendly).
	var syn: StateSynchronizer = entities.get(eid, null)
	if syn != null and pairs.size() > 0:
		syn.apply_delta(pairs)
		syn.mark_many_by_id(pairs, false)
		_track_client_pairs(eid, pairs)



@rpc("authority", "reliable")
func on_props_bootstrap(_bytes: PackedByteArray) -> void:
	pass


@rpc("authority", "reliable")
func on_props_delta(_bytes: PackedByteArray) -> void:
	pass


var _client_owned_fids: Dictionary[int, bool] = {
	PathRegistry.id_of(":position"): true,
	PathRegistry.id_of(":anim"): true,
	PathRegistry.id_of(":flipped"): true,
	PathRegistry.id_of(":pivot"): true,
}

func _is_client_owned(fid: int) -> bool:
	return _client_owned_fids.get(fid, false)

func _should_suppress_for_owner(eid: int, fid: int, value: Variant, now_ms: int) -> bool:
	# On ne supprime que pour les champs client-owned.
	if not _is_client_owned(fid):
		return false

	var m: Dictionary = _owner_recent.get(eid, {})
	var rec: Dictionary = m.get(fid, {})
	if rec.is_empty():
		return false

	if now_ms - int(rec.get("t", 0)) > owner_predict_suppress_ms:
		return false

	# Égalité "tolérante" pour éviter les micro-diffs float.
	var wt := PathRegistry.type_of(fid)
	match wt:
		PathRegistry.WIRE_VEC2_F32:
			return (Vector2(rec["v"]) - Vector2(value)).length_squared() < 0.0001
		PathRegistry.WIRE_F32:
			return abs(float(rec["v"]) - float(value)) < 0.001
		_:
			return rec["v"] == value


func _prune_owner_recent(max_age_ms: int) -> void:
	var now := Time.get_ticks_msec()
	for eid: int in _owner_recent.keys():
		var m: Dictionary = _owner_recent[eid]
		for fid_any in m.keys():
			var rec: Dictionary = m[fid_any]
			if now - int(rec.get("t", 0)) > max_age_ms:
				m.erase(fid_any)
		if m.is_empty():
			_owner_recent.erase(eid)
