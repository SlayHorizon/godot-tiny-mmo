class_name WireCodec
extends Node
## Binary codec for deltas and bootstrap based on PathRegistry's wire types.
## Build bytes using StreamPeerBuffer, then send a single PackedByteArray over RPC.

# --- Encode helpers -----------------------------------------------------------

static func _put_u8(spb: StreamPeerBuffer, v: int) -> void:
	spb.put_u8(v)


static func _put_u16(spb: StreamPeerBuffer, v: int) -> void:
	spb.put_u16(v)


static func _put_u32(spb: StreamPeerBuffer, v: int) -> void:
	spb.put_u32(v)


static func _put_f32(spb: StreamPeerBuffer, v: float) -> void:
	spb.put_float(v)


static func _put_vec2(spb: StreamPeerBuffer, v: Vector2) -> void:
	spb.put_float(v.x)
	spb.put_float(v.y)


# --- Decode helpers -----------------------------------------------------------

static func _get_u8(spb: StreamPeerBuffer) -> int:
	return spb.get_u8()


static func _get_u16(spb: StreamPeerBuffer) -> int:
	return spb.get_u16()


static func _get_u32(spb: StreamPeerBuffer) -> int:
	return spb.get_u32()


static func _get_f32(spb: StreamPeerBuffer) -> float:
	return spb.get_float()


static func _get_vec2(spb: StreamPeerBuffer) -> Vector2:
	var x: float = spb.get_float()
	var y: float = spb.get_float()
	return Vector2(x, y)


# --- Value (de)serialization by wire type ------------------------------------

static func _encode_value(spb: StreamPeerBuffer, wire_type: int, value: Variant) -> void:
	match wire_type:
		PathRegistry.WIRE_BOOL:
			var b: bool = bool(value)
			_put_u8(spb, 1 if b else 0)
		PathRegistry.WIRE_I32:
			_put_u32(spb, int(value))
		PathRegistry.WIRE_F32:
			_put_f32(spb, float(value))
		PathRegistry.WIRE_VEC2_F32:
			_put_vec2(spb, value as Vector2)
		_:
			# Variant fallback (larger, but safe)
			spb.put_var(value)


static func _decode_value(spb: StreamPeerBuffer, wire_type: int) -> Variant:
	match wire_type:
		PathRegistry.WIRE_BOOL:
			return _get_u8(spb) != 0
		PathRegistry.WIRE_I32:
			return _get_u32(spb)
		PathRegistry.WIRE_F32:
			return _get_f32(spb)
		PathRegistry.WIRE_VEC2_F32:
			return _get_vec2(spb)
		_:
			return spb.get_var()


static func encode_entity_block(eid: int, pairs: Array) -> PackedByteArray:
	var spb: StreamPeerBuffer = StreamPeerBuffer.new()
	_put_u32(spb, eid)
	var n: int = pairs.size()
	_put_u16(spb, n)
	for i in range(n):
		var p: Array = pairs[i]
		var pid: int = int(p[0])
		_put_u16(spb, pid)
		var wt: int = PathRegistry.type_of(pid)
		_encode_value(spb, wt, p[1])
	return spb.data_array


static func assemble_delta_from_blocks(blocks_bytes: Array) -> PackedByteArray:
	var spb: StreamPeerBuffer = StreamPeerBuffer.new()
	_put_u16(spb, blocks_bytes.size())
	for i in range(blocks_bytes.size()):
		var bb: PackedByteArray = blocks_bytes[i]
		spb.put_data(bb)
	return spb.data_array


# -------------------- DELTA ---------------------------------------------------

## blocks = [ { "eid": int, "pairs": Array[[pid:int, value], ...] }, ... ]
static func encode_delta(blocks: Array) -> PackedByteArray:
	var spb: StreamPeerBuffer = StreamPeerBuffer.new()
	var block_count: int = blocks.size()
	_put_u16(spb, block_count)

	for i in range(block_count):
		var block: Dictionary = blocks[i]
		var eid: int = int(block["eid"])
		_put_u32(spb, eid)

		var pairs: Array = block.get("pairs", [])
		var pair_count: int = pairs.size()
		_put_u16(spb, pair_count)

		for j in range(pair_count):
			var p: Array = pairs[j]
			var pid: int = int(p[0])
			_put_u16(spb, pid)
			var wt: int = PathRegistry.type_of(pid)
			_encode_value(spb, wt, p[1])

	return spb.data_array


static func decode_delta(data: PackedByteArray) -> Array:
	var spb: StreamPeerBuffer = StreamPeerBuffer.new()
	spb.data_array = data

	var block_count: int = _get_u16(spb)
	var out: Array = []

	for _i in range(block_count):
		var eid: int = _get_u32(spb)
		var pair_count: int = _get_u16(spb)
		var pairs: Array = []

		for _j in range(pair_count):
			var pid: int = _get_u16(spb)
			var wt: int = PathRegistry.type_of(pid)
			var v: Variant = _decode_value(spb, wt)
			pairs.append([pid, v])

		out.append({ "eid": eid, "pairs": pairs })

	return out


# -------------------- BOOTSTRAP ----------------------------------------------

## map_updates = [[pid:int, path:String, wire_type:int], ...]
## objects     = [ { "eid": int, "pairs": Array[[pid:int, value], ...] }, ... ]
static func encode_bootstrap(map_updates: Array, objects: Array) -> PackedByteArray:
	var spb: StreamPeerBuffer = StreamPeerBuffer.new()

	# Mapping
	var updates_count: int = map_updates.size()
	_put_u16(spb, updates_count)
	for i in range(updates_count):
		var u: Array = map_updates[i]
		var pid: int = int(u[0])
		var path: String = String(u[1])
		var wt: int = int(u[2])
		_put_u16(spb, pid)
		spb.put_utf8_string(path) # writes len + bytes
		_put_u8(spb, wt)

	# Objects
	var obj_count: int = objects.size()
	_put_u16(spb, obj_count)
	for i in range(obj_count):
		var obj: Dictionary = objects[i]
		var eid: int = int(obj["eid"])
		_put_u32(spb, eid)

		var pairs: Array = obj.get("pairs", [])
		var pair_count: int = pairs.size()
		_put_u16(spb, pair_count)

		for j in range(pair_count):
			var p: Array = pairs[j]
			var pid2: int = int(p[0])
			_put_u16(spb, pid2)
			var wt2: int = PathRegistry.type_of(pid2)
			_encode_value(spb, wt2, p[1])

	return spb.data_array


static func decode_bootstrap(data: PackedByteArray) -> Dictionary:
	var spb: StreamPeerBuffer = StreamPeerBuffer.new()
	spb.data_array = data

	# Mapping
	var updates_count: int = _get_u16(spb)
	var updates: Array = []
	for _i in range(updates_count):
		var pid: int = _get_u16(spb)
		var path: String = spb.get_utf8_string()
		var wt: int = _get_u8(spb)
		updates.append([pid, path, wt])
	
	# IMPORTANT PLS APPLY UPDATES BEFORE DECODING
	if updates.size():
		PathRegistry.apply_map_updates(updates)
	
	# Objects
	var obj_count: int = _get_u16(spb)
	var objects: Array = []
	for _j in range(obj_count):
		var eid: int = _get_u32(spb)
		var pair_count: int = _get_u16(spb)
		var pairs: Array = []

		for _k in range(pair_count):
			var pid2: int = _get_u16(spb)
			var wt2: int = PathRegistry.type_of(pid2)
			var v: Variant = _decode_value(spb, wt2)
			pairs.append([pid2, v])

		objects.append({ "eid": eid, "pairs": pairs })

	return { "map_updates": updates, "objects": objects }


# WireCodec.gd — helpers “container block”

static func encode_container_block(eid: int, spawns: Array, pairs: Array, despawns: Array) -> PackedByteArray:
	var spb := StreamPeerBuffer.new()
	_put_u32(spb, eid)

	# spawns
	_put_u16(spb, spawns.size())
	for s in spawns:
		_put_u16(spb, int(s[0])) # child_id
		_put_u16(spb, int(s[1])) # scene_id (u16 -> élargis si besoin)

	# pairs
	_put_u16(spb, pairs.size())
	for p in pairs:
		var cpid: int = int(p[0])
		var fid: int = cpid & 0xFFFF
		_put_u32(spb, cpid)
		_encode_value(spb, PathRegistry.type_of(fid), p[1])

	# despawns
	_put_u16(spb, despawns.size())
	for d in despawns:
		_put_u16(spb, int(d))

	return spb.data_array


static func decode_container_block(data: PackedByteArray) -> Dictionary:
	var spb := StreamPeerBuffer.new()
	spb.data_array = data

	var eid: int = _get_u32(spb)

	var spn_n: int = _get_u16(spb)
	var spawns: Array = []
	for _i in range(spn_n):
		spawns.append([_get_u16(spb), _get_u16(spb)])

	var pr_n: int = _get_u16(spb)
	var pairs: Array = []
	for _j in range(pr_n):
		var cpid: int = _get_u32(spb)
		var fid: int = cpid & 0xFFFF
		pairs.append([cpid, _decode_value(spb, PathRegistry.type_of(fid))])

	var dsp_n: int = _get_u16(spb)
	var despawns: Array = []
	for _k in range(dsp_n):
		despawns.append(_get_u16(spb))

	return { "eid": eid, "spawns": spawns, "pairs": pairs, "despawns": despawns }


static func encode_container_block_named(eid: int, spawns: Array, pairs: Array, despawns: Array, ops_named: Array) -> PackedByteArray:
	var spb := StreamPeerBuffer.new()
	_put_u32(spb, eid)

	# spawns
	_put_u16(spb, spawns.size())
	for s in spawns:
		_put_u16(spb, int(s[0])) # child_id
		_put_u16(spb, int(s[1])) # scene_id

	# pairs
	_put_u16(spb, pairs.size())
	for p in pairs:
		var cpid: int = int(p[0])
		var fid: int = cpid & 0xFFFF
		_put_u32(spb, cpid)
		_encode_value(spb, PathRegistry.type_of(fid), p[1])

	# despawns
	_put_u16(spb, despawns.size())
	for d in despawns:
		_put_u16(spb, int(d))

	# ops_named = [[child_id, method:String, args:Array], ...]
	_put_u16(spb, ops_named.size())
	for o in ops_named:
		_put_u16(spb, int(o[0]))                   # child_id
		spb.put_utf8_string(String(o[1]))          # method
		var args: Array = o[2] as Array if o.size() else []
		_put_u8(spb, args.size())                  # arg count
		for a in args:
			spb.put_var(a)                          # generic (ok, rarement gros)

	return spb.data_array


static func decode_container_block_named(data: PackedByteArray) -> Dictionary:
	var spb := StreamPeerBuffer.new()
	spb.data_array = data

	var eid: int = _get_u32(spb)

	var spn_n: int = _get_u16(spb)
	var spawns: Array = []
	for _i in range(spn_n):
		spawns.append([_get_u16(spb), _get_u16(spb)])

	var pr_n: int = _get_u16(spb)
	var pairs: Array = []
	for _j in range(pr_n):
		var cpid: int = _get_u32(spb)
		var fid: int = cpid & 0xFFFF
		pairs.append([cpid, _decode_value(spb, PathRegistry.type_of(fid))])

	var dsp_n: int = _get_u16(spb)
	var despawns: Array = []
	for _k in range(dsp_n):
		despawns.append(_get_u16(spb))

	var op_n: int = _get_u16(spb)
	var ops_named: Array = []
	for _m in range(op_n):
		var cid := _get_u16(spb)
		var method := spb.get_utf8_string()
		var argc := _get_u8(spb)
		var args: Array = []
		for _t in range(argc):
			args.append(spb.get_var())
		ops_named.append([cid, method, args])

	return { "eid": eid, "spawns": spawns, "pairs": pairs, "despawns": despawns, "ops_named": ops_named }


static func peek_container_block_named(data: PackedByteArray) -> Dictionary:
	# Cheap peek: only read the first 4 bytes (eid) without decoding the whole block.
	var spb := StreamPeerBuffer.new()
	spb.data_array = data
	var eid: int = _get_u32(spb)
	return { "eid": eid }
