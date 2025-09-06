# Mixed SyncAttribute and HealthAttribute that should inherit from SyncAttribute
extends Node


@export var state_synchronizer: StateSynchronizer

var base_value: SyncProperty
var current_value: SyncProperty


func _init() -> void:
	# Not typing NodePath because we can't do NodePath + NodePath.
	var node_path: String = state_synchronizer.get_path_to(self)
	current_value = SyncProperty.new(node_path + ":current_value")
	base_value = SyncProperty.new(node_path + ":base_value")
	
	# 
	if is_multiplayer_authority():
		current_value.set_setter(server_set_health)
	else:
		current_value.set_setter(client_set_health)


func get_health() -> float:
	return base_value.get_value()


func server_set_health(value: float) -> void:
	current_value._value = value
	state_synchronizer.mark_dirty_by_id(current_value._pid, value, false)


func client_set_health(value: float) -> void:
	#display_damage()
	#progress_bar.value = value
	current_value._value = value


class SyncProperty:
	
	var _value: float
	var _path: NodePath
	var _pid: int
	
	var _setter: Callable = _default_setter
	var _getter: Callable = _default_getter
	
	
	func _init(path: NodePath) -> void:
		_path = path
		_pid = PathRegistry.id_of(path)
	
	
	func set_getter(new_getter: Callable) -> void:
		_setter = new_getter
	
	
	func set_setter(new_setter: Callable) -> void:
		_setter = new_setter


	func get_value() -> float:
		return _getter.call()
	
	
	func set_value(value: float) -> void:
		_setter.call(value)
	
	
	func _default_setter(value: float)-> void:
		_value = value
	
	
	func _default_getter() -> float:
		return _value
