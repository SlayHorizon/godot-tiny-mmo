class_name AttributesMirror
extends Node
## Allow StateSynchronizer to modify attributes from NodePath.
## It's really tricky, we may change that later.


signal attribute_local_changed(attr: StringName, value: float, max_value: float)

var _vals: Dictionary[StringName, float] = {}
var _maxs: Dictionary[StringName, float] = {}
var _keys: PackedStringArray = []


func register_attr(attr: StringName) -> void:
	if _keys.has(attr):
		return
	_keys.append(attr)
	notify_property_list_changed()


func set_pair(attr: StringName, value: float, max_value: float) -> void:
	_vals[attr] = value
	_maxs[attr] = max_value
	attribute_local_changed.emit(attr, value, max_value)


func get_value(attr: StringName) -> float:
	return _vals.get(attr, 0.0)


func get_max(attr: StringName) -> float:
	return _maxs.get(attr, 0.0)


func _get_property_list() -> Array:
	var properties: Array[Dictionary] = []
	for key: String in _keys:
		properties.append({
			"name": key,
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_DEFAULT
		})
		properties.append({
			"name": key + "_max",
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_DEFAULT
		})
	return properties


func _get(property: StringName) -> Variant:
	if property.ends_with("_max"):
		return _maxs.get(property.trim_suffix("_max"), 0.0)
	return _vals.get(property, 0.0)


func _set(property: StringName, value: Variant) -> bool:
	if property.ends_with("_max"):
		property = property.trim_suffix("_max")
		_maxs[property] = float(value)
		attribute_local_changed.emit(property, _vals.get(property, 0.0), _maxs[property])
	else:
		_vals[property] = float(value)
		attribute_local_changed.emit(
			property,
			_vals[property],
			_maxs.get(property, 0.0)
		)
	return true
