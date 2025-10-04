class_name StateSynchronizerManagerServer
extends Node
## Per-instance manager.
## - Entities (hot): own StateSynchronizer per EID, pre-encode per-entity blocks, per-peer assembly (skip-self).
## - Props (cold): own ReplicatedPropsContainer per CID (container id), broadcast or AOI later.
## - Sends PathRegistry map updates on bootstrap AND whenever the schema version changes.

enum AOIMode {
	NONE,
	GRID,
}

@export var aoi_mode: AOIMode = AOIMode.NONE
@export var aoi_grid_size: Vector2i = Vector2i(512, 512)
@export var visible_grid_size: int = 2

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
		_update_zones_one_shot()
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
		# Client apply order: spawns → ops_named → pairs → despawns
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


# --- Owner correction (server → owner only)

func send_correction_to_owner(eid: int, pairs: Array) -> void:
	var owner_peer_id: int = eid  # Replace by real ownership map later.
	if not peers.has(owner_peer_id):
		return
	if pairs.is_empty():
		return
	var bb: PackedByteArray = WireCodec.encode_entity_block(eid, pairs)
	var bytes: PackedByteArray = WireCodec.assemble_delta_from_blocks([bb])
	on_state_delta.rpc_id(owner_peer_id, bytes)


# --- Client-side handlers mirrored for RPC presence

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
		Wire.Type.VEC2_F32:
			return (Vector2(rec["v"]) - Vector2(value)).length_squared() < 0.0001
		Wire.Type.F32:
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


# AOI - in construction
var _cell_to_eids: Dictionary[Vector2i, PackedInt32Array]
var _eid_to_cell: Dictionary[int, Vector2i]


func _eid_position(eid: int) -> Vector2:
	var syn: StateSynchronizer = entities.get(eid, null)
	if syn == null:
		return Vector2.ZERO
	# We rely on your PathRegistry id for ":position"
	var fid: int = PathRegistry.id_of(":position")
	var state: Variant= syn.last_applied  # internal, but fine inside manager
	if state.has(fid):
		return Vector2(state[fid])
	return Vector2.ZERO

func _pos_to_cell(p: Vector2) -> Vector2i:
	var cs := Vector2(aoi_grid_size)
	return Vector2i(floor(p.x / cs.x), floor(p.y / cs.y))

func _rebuild_aoi_index() -> void:
	_cell_to_eids.clear()
	_eid_to_cell.clear()
	for eid in entities.keys():
		var c := _pos_to_cell(_eid_position(eid))
		_eid_to_cell[eid] = c
		var list: PackedInt32Array = _cell_to_eids.get(c, PackedInt32Array())
		list.append(eid)
		_cell_to_eids[c] = list

func _aoi_entities_for(peer_id: int) -> Array:
	match aoi_mode:
		AOIMode.NONE:
			return entities.keys()
		AOIMode.GRID:
			# Use the owner’s entity as the camera pivot or use a real camera ?
			var pivot_eid: int = peer_id
			# If the peer owns multiple eids
			# or later we can store a "view_eid per peer" ?
			var center: Vector2i = _eid_to_cell.get(pivot_eid, Vector2i.ZERO)
			var out := []
			for dx in range(-visible_grid_size, visible_grid_size + 1):
				for dy in range(-visible_grid_size, visible_grid_size + 1):
					var cell: Vector2i= Vector2i(center.x + dx, center.y + dy)
					var list: PackedInt32Array = _cell_to_eids.get(cell, PackedInt32Array())
					for i in list:
						out.append(i)
			return out
		_:
			return entities.keys()



# --- Zoning (server)
var _zone_cell_size: Vector2i = Vector2i(64, 64)
var _zone_origin_ws: Vector2 = Vector2.ZERO  # world-space anchor for cell (0,0)
var _zone_cols: int = 0
var _zone_rows: int = 0
var _zone_default_flags: int = 0
var _zone_grid: PackedInt32Array = PackedInt32Array()

var _eid_zone_cell_idx: Dictionary[int, int] = {}   # eid -> linear cell index
var _eid_zone_flags: Dictionary[int, int] = {}      # eid -> packed flags (mode+modifiers)
var _eid_zone_last_change_ms: Dictionary[int, int] = {}  # hysteresis
var _zone_hysteresis_ms: int = 300

func init_zones_from_map(map: Map) -> void:
	var data: Dictionary = map.get_zone_authoring_data()

	_zone_cell_size = data.get("zone_cell_size", Vector2i(64, 64))
	_zone_origin_ws = Vector2(data.get("zone_origin", Vector2i.ZERO))

	# Pack defaults into our int flags: bit 0 = PVP (1), 0 = SAFE; bits 1.. = modifiers
	var is_pvp: bool = (int(data.get("default_mode", Map.ZoneMode.SAFE)) == Map.ZoneMode.PVP)
	var mods: int = int(data.get("default_modifiers", 0))
	_zone_default_flags = (1 if is_pvp else 0) | (mods << 1)

	_build_zone_grid_from_authoring(data)  # fills _zone_grid/_zone_cols/_zone_rows


func _build_zone_grid_from_authoring(data: Dictionary) -> void:
	var patches: Array = data.get("patches", [])
	# If no patches: trivial — one cell using defaults; we won’t even look it up later.
	if patches.is_empty():
		_zone_cols = 1
		_zone_rows = 1
		_zone_grid = PackedInt32Array([_zone_default_flags])
		return

	# Compute tight bounds from all polygons (AABB in 2D).
	var first: bool = true
	var minp: Vector2 = Vector2.ZERO
	var maxp: Vector2 = Vector2.ZERO
	for p_any in patches:
		var polys: Array = Dictionary(p_any).get("polygons_world", [])
		for poly_any in polys:
			var poly: PackedVector2Array = poly_any
			for v in poly:
				var pt: Vector2 = v
				if first:
					minp = pt; maxp = pt; first = false
				else:
					minp.x = min(minp.x, pt.x); minp.y = min(minp.y, pt.y)
					maxp.x = max(maxp.x, pt.x); maxp.y = max(maxp.y, pt.y)

	# Align bounds to our cell grid anchored at _zone_origin_ws
	var cs: Vector2 = Vector2(_zone_cell_size)
	var rel_min: Vector2 = (minp - _zone_origin_ws) / cs
	var rel_max: Vector2 = (maxp - _zone_origin_ws) / cs
	var cell_min: Vector2i = Vector2i(floor(rel_min.x), floor(rel_min.y))
	var cell_max: Vector2i = Vector2i(ceil(rel_max.x),  ceil(rel_max.y))

	_zone_cols = max(1, cell_max.x - cell_min.x)
	_zone_rows = max(1, cell_max.y - cell_min.y)
	_zone_grid.resize(_zone_cols * _zone_rows)
	for i in _zone_grid.size():
		_zone_grid[i] = _zone_default_flags

	# This is the world-space origin of cell (0,0) in our raster box.
	_zone_origin_ws = _zone_origin_ws + Vector2(cell_min * _zone_cell_size)

	# Sort patches by priority (low→high), later wins.
	patches.sort_custom(func(a, b):
		return int(Dictionary(a).get("priority", 0)) < int(Dictionary(b).get("priority", 0))
	)

	# Paint each patch: center-in-poly; SAFE bias on borders (all 4 corners must be inside for PVP flip).
	for p_any in patches:
		var p: Dictionary = p_any
		var mode_ov: int = int(p.get("mode_override", 0)) # INHERIT=0, SAFE=1, PVP=2
		var add_mod: int = int(p.get("add_modifiers", 0))
		var rem_mod: int = int(p.get("remove_modifiers", 0))
		var polys: Array = p.get("polygons", [])

		# Per polygon piece
		for poly_any in polys:
			var poly: PackedVector2Array = poly_any
			# Coarse cell AABB for this poly
			var poly_min: Vector2 = poly[0]
			var poly_max: Vector2 = poly[0]
			for v in poly:
				poly_min.x = min(poly_min.x, v.x); poly_min.y = min(poly_min.y, v.y)
				poly_max.x = max(poly_max.x, v.x); poly_max.y = max(poly_max.y, v.y)
			var cmin: Vector2i = _ws_pos_to_local_cell(poly_min)
			var cmax: Vector2i = _ws_pos_to_local_cell(poly_max)
			# expand one cell to be safe
			cmin.x = clamp(cmin.x - 1, 0, _zone_cols - 1)
			cmin.y = clamp(cmin.y - 1, 0, _zone_rows - 1)
			cmax.x = clamp(cmax.x + 1, 0, _zone_cols - 1)
			cmax.y = clamp(cmax.y + 1, 0, _zone_rows - 1)

			for cy in range(cmin.y, cmax.y + 1):
				for cx in range(cmin.x, cmax.x + 1):
					var idx: int = cy * _zone_cols + cx
					var center: Vector2 = _cell_center_ws(cx, cy)
					var in_center: bool = Geometry2D.is_point_in_polygon(center, poly)
					if not in_center:
						continue

					var prev: int = _zone_grid[idx]
					var cur_pvp: bool = (prev & 1) == 1
					var cur_mods: int = prev >> 1

					# Compute wanted mode/mods after override/add/remove
					var want_pvp: bool = cur_pvp
					if mode_ov == 1:     # SAFE
						want_pvp = false
					elif mode_ov == 2:   # PVP
						# SAFE bias: require all four corners inside to switch to PVP
						var half: Vector2 = cs * 0.5
						var tl: Vector2 = center + Vector2(-half.x, -half.y)
						var tr: Vector2 = center + Vector2( half.x, -half.y)
						var br: Vector2 = center + Vector2( half.x,  half.y)
						var bl: Vector2 = center + Vector2(-half.x,  half.y)
						var all_inside: bool = (
							Geometry2D.is_point_in_polygon(tl, poly)
							and Geometry2D.is_point_in_polygon(tr, poly)
							and Geometry2D.is_point_in_polygon(br, poly)
							and Geometry2D.is_point_in_polygon(bl, poly)
						)
						if all_inside:
							want_pvp = true
					# modifiers: add then remove
					var want_mods: int = (cur_mods | add_mod) & (~rem_mod)

					_zone_grid[idx] = (1 if want_pvp else 0) | (want_mods << 1)

func _ws_pos_to_local_cell(ws: Vector2) -> Vector2i:
	var rel: Vector2 = (ws - _zone_origin_ws) / Vector2(_zone_cell_size)
	return Vector2i(int(floor(rel.x)), int(floor(rel.y)))

func _cell_center_ws(cx: int, cy: int) -> Vector2:
	var base: Vector2 = _zone_origin_ws + Vector2(cx * _zone_cell_size.x, cy * _zone_cell_size.y)
	return base + Vector2(_zone_cell_size) * 0.5


func _update_zones_one_shot() -> void:
	# If there’s effectively no grid (interior with no patches), nothing to do; everyone uses defaults in validators.
	if _zone_grid.is_empty() or peers.is_empty():
		return

	var now_ms: int = Time.get_ticks_msec()
	for eid: int in entities.keys():
		var pos: Vector2 = _eid_position(eid)
		# Convert to raster-local cell (clamped)
		var rel: Vector2 = (pos - _zone_origin_ws) / Vector2(_zone_cell_size)
		var cx: int = clamp(int(floor(rel.x)), 0, _zone_cols - 1)
		var cy: int = clamp(int(floor(rel.y)), 0, _zone_rows - 1)
		var idx: int = cy * _zone_cols + cx

		var last_idx: int = _eid_zone_cell_idx.get(eid, -1)
		if idx == last_idx:
			continue

		var new_flags: int = _zone_grid[idx]
		var old_flags: int = _eid_zone_flags.get(eid, _zone_default_flags)

		# Hysteresis only when flipping SAFE <-> PVP (bit 0)
		var old_pvp: bool = (old_flags & 1) == 1
		var new_pvp: bool = (new_flags & 1) == 1
		if old_pvp != new_pvp:
			var last_ms: int = _eid_zone_last_change_ms.get(eid, 0)
			if now_ms - last_ms < _zone_hysteresis_ms:
				# still within grace; skip this flip
				continue
			_eid_zone_last_change_ms[eid] = now_ms

		_eid_zone_cell_idx[eid] = idx
		_eid_zone_flags[eid] = new_flags

		# Notify owner with minimal UI state (server-authoritative fields)
		entities[eid].root_node.zone_flags = new_flags
		
		#print((new_flags & 1) != 0)
		var pairs: Array = [
			[PathRegistry.id_of(":zone_flags"), new_flags],
		]
		send_correction_to_owner(eid, pairs)
