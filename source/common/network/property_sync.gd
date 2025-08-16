class_name PropertySync
extends RefCounted
## Holds a property NodePath and lazily caches its field ID (pid).
## Lets you mark authoritative changes through a StateSynchronizer without repeating boilerplate.

var path: NodePath
var _pid: int = 0


func _init(p: NodePath) -> void:
	path = p


func pid() -> int:
	if _pid == 0:
		_pid = PathRegistry.ensure_id(String(path))
	return _pid


func mark(sync: StateSynchronizer, value: Variant, only_if_changed: bool = true) -> void:
	if sync == null:
		return
	sync.mark_dirty_by_id(pid(), value, only_if_changed)
