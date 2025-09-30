class_name WireCodec
extends Node
## Binary codec for deltas and bootstrap based on PathRegistry's wire types.
## Build bytes using StreamPeerBuffer, then send a single PackedByteArray over RPC.


# put_double / f64 / 64 bits
# put_float / f32 / 32 bits / float, single precision
# put_half / f16 / 16 bits/ half, half precision


static func _new_buff() -> StreamPeerBuffer:
	var stream_peer_buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	stream_peer_buffer.big_endian = false
	return stream_peer_buffer


static func _from_bytes(bytes: PackedByteArray) -> StreamPeerBuffer:
	var stream_peer_buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	stream_peer_buffer.big_endian = false
	stream_peer_buffer.data_array = bytes
	return stream_peer_buffer


#region vec2helpers
static func _put_vec2(spb: StreamPeerBuffer, v: Vector2) -> void:
	spb.put_float(v.x)
	spb.put_float(v.y)


static func _get_vec2(spb: StreamPeerBuffer) -> Vector2:
	var x: float = spb.get_float()
	var y: float = spb.get_float()
	return Vector2(x, y)
#endregion


# Value (de)serialization by wire type
static func _encode_value(spb: StreamPeerBuffer, wire_type: int, value: Variant) -> void:
	match wire_type:
		PathRegistry.WIRE_BOOL: #when typeof(value) == TYPE_BOOL:
			spb.put_u8(int(bool(value)))
		PathRegistry.WIRE_I32:
			spb.put_u32(value)
		PathRegistry.WIRE_F32:
			spb.put_float(value)
		PathRegistry.WIRE_VEC2_F32:
			_put_vec2(spb, value as Vector2)
		_:
			# Variant fallback (larger, but safe)
			spb.put_var(value)


static func _decode_value(spb: StreamPeerBuffer, wire_type: int) -> Variant:
	match wire_type:
		PathRegistry.WIRE_BOOL:
			return spb.get_u8() != 0
		PathRegistry.WIRE_I32:
			return spb.get_u32()
		PathRegistry.WIRE_F32:
			return spb.get_float()
		PathRegistry.WIRE_VEC2_F32:
			return _get_vec2(spb)
		_:
			return spb.get_var()


static func encode_entity_block(eid: int, pairs: Array) -> PackedByteArray:
	var spb: StreamPeerBuffer = _new_buff()
	spb.put_u32(eid)
	var n: int = pairs.size()
	spb.put_u16(n)
	for i in range(n):
		var p: Array = pairs[i]
		var pid: int = int(p[0])
		spb.put_u16(pid)
		var wt: int = PathRegistry.type_of(pid)
		_encode_value(spb, wt, p[1])
	return spb.data_array


static func assemble_delta_from_blocks(blocks_bytes: Array) -> PackedByteArray:
	var spb: StreamPeerBuffer = _new_buff()
	spb.put_u16(blocks_bytes.size())
	for i in range(blocks_bytes.size()):
		var bb: PackedByteArray = blocks_bytes[i]
		spb.put_data(bb)
	return spb.data_array


#region delta
## blocks = [ { "eid": int, "pairs": Array[[pid:int, value], ...] }, ... ]
static func encode_delta(blocks: Array) -> PackedByteArray:
	var spb := _new_buff()
	spb.put_u16(blocks.size())

	for block in blocks:
		var eid: int = int(block["eid"])
		spb.put_u32(eid)

		var pairs: Array = block.get("pairs", [])
		spb.put_u16(pairs.size())

		for p in pairs:
			var pid: int = int(p[0])
			spb.put_u16(pid)
			var wt: int = PathRegistry.type_of(pid)
			_encode_value(spb, wt, p[1])

	return spb.data_array


static func decode_delta(data: PackedByteArray) -> Array:
	var spb := _from_bytes(data)

	var block_count := spb.get_u16()
	var out: Array = []

	for _i in block_count:
		var eid := spb.get_u32()
		var pair_count := spb.get_u16()
		var pairs: Array = []
		for _j in pair_count:
			var pid := spb.get_u16()
			var wt := PathRegistry.type_of(pid)
			pairs.append([pid, _decode_value(spb, wt)])
		out.append({ "eid": eid, "pairs": pairs })

	return out
#endregion


#region bootstrap
## map_updates = [[pid:int, path:String, wire_type:int], ...]
## objects     = [ { "eid": int, "pairs": Array[[pid:int, value], ...] }, ... ]
static func encode_bootstrap(map_updates: Array, objects: Array) -> PackedByteArray:
	var spb: StreamPeerBuffer = StreamPeerBuffer.new()

	# Mapping
	var updates_count: int = map_updates.size()
	spb.put_u16(updates_count)
	for i in range(updates_count):
		var u: Array = map_updates[i]
		var pid: int = int(u[0])
		var path: String = String(u[1])
		var wt: int = int(u[2])
		spb.put_u16(pid)
		spb.put_utf8_string(path) # writes len + bytes
		spb.put_u8(wt)

	# Objects
	var obj_count: int = objects.size()
	spb.put_u16(obj_count)
	for i in range(obj_count):
		var obj: Dictionary = objects[i]
		var eid: int = int(obj["eid"])
		spb.put_u32(eid)

		var pairs: Array = obj.get("pairs", [])
		var pair_count: int = pairs.size()
		spb.put_u16(pair_count)

		for j in range(pair_count):
			var p: Array = pairs[j]
			var pid2: int = int(p[0])
			spb.put_u16(pid2)
			var wt2: int = PathRegistry.type_of(pid2)
			_encode_value(spb, wt2, p[1])

	return spb.data_array


static func decode_bootstrap(data: PackedByteArray) -> Dictionary:
	var spb := _from_bytes(data)

	# Mapping
	var updates_count := spb.get_u16()
	var updates: Array = []
	for _i in range(updates_count):
		var pid := spb.get_u16()
		var path := spb.get_utf8_string()
		var wt := spb.get_u8()
		updates.append([pid, path, wt])

	# IMPORTANT: apply mapping before decoding objects
	if updates.size() > 0:
		PathRegistry.apply_map_updates(updates)

	# Objects
	var obj_count := spb.get_u16()
	var objects: Array = []
	for _j in range(obj_count):
		var eid := spb.get_u32()
		var pair_count := spb.get_u16()
		var pairs: Array = []
		for _k in range(pair_count):
			var pid2 := spb.get_u16()
			var wt2 := PathRegistry.type_of(pid2)
			var v: Variant = _decode_value(spb, wt2)
			pairs.append([pid2, v])
		objects.append({ "eid": eid, "pairs": pairs })

	return { "map_updates": updates, "objects": objects }
#endregion


#region container
static func encode_container_block_named(eid: int, spawns: Array, pairs: Array, despawns: Array, ops_named: Array) -> PackedByteArray:
	var spb := _new_buff()
	spb.put_u32(eid)

	# spawns
	spb.put_u16(spawns.size())
	for s in spawns:
		spb.put_u16(int(s[0])) # child_id
		spb.put_u16(int(s[1])) # scene_id

	# pairs
	spb.put_u16(pairs.size())
	for p in pairs:
		var cpid := int(p[0])
		var fid := cpid & 0xFFFF
		spb.put_u32(cpid)
		_encode_value(spb, PathRegistry.type_of(fid), p[1])

	# despawns
	spb.put_u16(despawns.size())
	for d in despawns:
		spb.put_u16(int(d))

	# ops_named = [[child_id, method:String, args:Array], ...]
	spb.put_u16(ops_named.size())
	for o in ops_named:
		spb.put_u16(int(o[0]))                    # child_id
		spb.put_utf8_string(String(o[1]))          # method
		var args: Array = o[2] as Array if o.size() else []
		spb.put_8(args.size())                  # arg count
		for a in args:
			spb.put_var(a)                          # generic (ok, rarement gros)

	return spb.data_array


static func decode_container_block_named(data: PackedByteArray) -> Dictionary:
	var spb := _from_bytes(data)

	var eid := spb.get_u32()

	var spn_n := spb.get_u16()
	var spawns: Array = []
	for _i in range(spn_n):
		spawns.append([spb.get_u16(), spb.get_u16()])

	var pr_n := spb.get_u16()
	var pairs: Array = []
	for _j in range(pr_n):
		var cpid := spb.get_u32()
		var fid := cpid & 0xFFFF
		pairs.append([cpid, _decode_value(spb, PathRegistry.type_of(fid))])

	var dsp_n := spb.get_u16()
	var despawns: Array = []
	for _k in range(dsp_n):
		despawns.append(spb.get_u16())

	var op_n := spb.get_u16()
	var ops_named: Array = []
	for _m in range(op_n):
		var cid := spb.get_u16()
		var method := spb.get_utf8_string()
		var argc := spb.get_u8()
		var args: Array = []
		for _t in range(argc):
			args.append(spb.get_var())
		ops_named.append([cid, method, args])

	return { "eid": eid, "spawns": spawns, "pairs": pairs, "despawns": despawns, "ops_named": ops_named }


static func peek_container_block_named(data: PackedByteArray) -> Dictionary:
	# Cheap peek: only read the first 4 bytes (eid) without decoding the whole block.
	var spb := StreamPeerBuffer.new()
	spb.data_array = data
	var eid := spb.get_u32()
	return { "eid": eid }
#endregion
