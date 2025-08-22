# AttributesMirror.gd
class_name AttributesMirror
extends Node
## Expose des propriétés dynamiques: "<attr>" et "<attr>_max".
## Permet à StateSynchronizer d'adresser les attributs via NodePath.

var _vals: Dictionary[StringName, float] = {}
var _maxs: Dictionary[StringName, float] = {}
var _keys: PackedStringArray = []


signal attribute_local_changed(attr: StringName, value: float, max_value: float)


func register_attr(attr: StringName) -> void:
	if _keys.has(String(attr)):
		return
	_keys.append(String(attr))
	notify_property_list_changed()


func set_pair(attr: StringName, value: float, max_value: float) -> void:
	_vals[attr] = value
	_maxs[attr] = max_value
	attribute_local_changed.emit(attr, value, max_value)

func get_value(attr: StringName) -> float:
	return _vals.get(attr, 0.0)

func get_max(attr: StringName) -> float:
	return _maxs.get(attr, 0.0)

# --- Dynamic properties for Godot inspector / set_indexed --------------------

func _get_property_list() -> Array:
	var props: Array = []
	for k in _keys:
		props.append({ "name": k, "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_DEFAULT })
		props.append({ "name": k + "_max", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_DEFAULT })
	return props


func _get(p: StringName) -> Variant:
	var s := String(p)
	if s.ends_with("_max"):
		var base := StringName(s.erase(s.length() - 4, 4))
		return _maxs.get(base, 0.0)
	return _vals.get(StringName(s), 0.0)


func _set(p: StringName, v: Variant) -> bool:
	var s := String(p)
	if s.ends_with("_max"):
		var base := StringName(s.erase(s.length() - 4, 4))
		_maxs[base] = float(v)
		attribute_local_changed.emit(base, _vals.get(base, 0.0), _maxs[base])
	else:
		var name := StringName(s)
		_vals[name] = float(v)
		attribute_local_changed.emit(name, _vals[name], _maxs.get(name, 0.0))
	return true
