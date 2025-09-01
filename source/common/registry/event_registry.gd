# EventRegistry.gd
class_name EventRegistry
## Compact mapping event <-> id.

static var _id_to_event: Dictionary[int, String] = {}
static var _event_to_id: Dictionary[String, int] = {}
static var _next_id: int = 1


static func reset() -> void:
	_id_to_event.clear()
	_event_to_id.clear()
	_next_id = 1


static func ensure_id(event: String) -> int:
	var existing: int = _event_to_id.get(event, 0)
	if existing:
		return existing
	var id: int = _next_id
	_next_id += 1
	_event_to_id[event] = id
	_id_to_event[id] = event
	return id


static func id_of(event: String) -> int:
	var v: Variant = _event_to_id.get(event, 0)
	return int(v)


static func event_of(id: int) -> String:
	var v: Variant = _id_to_event.get(id, "")
	return String(v)
