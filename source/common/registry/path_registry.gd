class_name PathRegistry
extends Node
## Global registry mapping property paths <-> field IDs with a wire type (schema-driven).
## Stores paths as String (best for wire/serialization) and caches NodePath for hot application.


static var _id_to_path: Dictionary[int, String]
static var _path_to_id: Dictionary[String, int]
static var _id_to_type: Dictionary[int, int]
static var _id_to_nodepath: Dictionary[int, NodePath]

static var _next_id: int = 1
static var _version: int = 1


static func _static_init() -> void:
	# Hardcoded fields
	register_field(":position", Wire.Type.VEC2_F32)
	register_field(":flipped", Wire.Type.BOOL)
	register_field(":anim", Wire.Type.VARIANT)
	register_field(":pivot", Wire.Type.F32)
	
	register_field(":scale", Wire.Type.VEC2_F32)
	
	register_field(":display_name", Wire.Type.VARIANT)
	
	register_field(":skin_id", Wire.Type.U16)
	
	register_field(":zone_flags", Wire.Type.U16)
	
	register_field("EquipmentComponent:mainhand_id", Wire.Type.U16)
	# Stat fields are registered at run-time.
	#register_field("AbilitySystemComponent/AttributesMirror:health",       WIRE_F32)


static func reset() -> void:
	_id_to_path.clear()
	_path_to_id.clear()
	_id_to_type.clear()
	_id_to_nodepath.clear()
	_next_id = 1
	_version = 1


## Register (or fetch) a field. If path exists, updates type if provided (>0).
static func register_field(path: String, wire_type: Wire.Type = Wire.Type.VARIANT) -> int:
	var id: int = _path_to_id.get(path, 0)
	if id == 0:
		id = _next_id
		_next_id += 1
		_path_to_id[path] = id
		_id_to_path[id] = path
		_id_to_type[id] = wire_type
		# invalidate any stale cache (defensive)
		_id_to_nodepath.erase(id)
		_version += 1
	else:
		if wire_type != Wire.Type.VARIANT and _id_to_type.get(id, Wire.Type.VARIANT) != wire_type:
			_id_to_type[id] = wire_type
			_version += 1
	return id


static func ensure_id(path: String) -> int:
	var existing: int = _path_to_id.get(path, 0)
	#print_debug(path, existing)
	if existing != 0:
		return existing
	return register_field(path, _id_to_type.get(existing, Wire.Type.VARIANT))


static func id_of(path: String) -> int:
	return _path_to_id.get(path, 0)


static func path_of(id: int) -> String:
	return _id_to_path.get(id, "")


## Hot-path helper: get a cached NodePath for 'id' (builds and caches on miss).
static func nodepath_of(id: int) -> NodePath:
	var np: NodePath = _id_to_nodepath.get(id, NodePath(""))
	if not np.is_empty():
		return np
	var s: String = _id_to_path.get(id, "")
	if s == "":
		return NodePath("")
	np = NodePath(s)
	_id_to_nodepath[id] = np
	return np


static func type_of(id: int) -> int:
	return _id_to_type.get(id, Wire.Type.VARIANT)


static func version() -> int:
	return _version


## Map updates for bootstrap/diffs: [[pid:int, path:String, wire_type:int], ...]
static func get_full_map_updates() -> Array:
	var out: Array = []
	for id in _id_to_path.keys():
		out.append([int(id), _id_to_path[id], _id_to_type.get(id, Wire.Type.VARIANT)])
	return out


static func apply_map_updates(updates: Array) -> void:
	if updates.is_empty():
		return
	for u in updates:
		var pid: int = int(u[0])
		var path: String = String(u[1])
		var wtype: int = int(u[2])
		_id_to_path[pid] = path
		_path_to_id[path] = pid
		_id_to_type[pid] = wtype
		_next_id = max(_next_id, pid + 1)
		_id_to_nodepath.erase(pid) # will be rebuilt on demand
	_version += 1
