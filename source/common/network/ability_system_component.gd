# AbilitySystemComponent.gd
class_name AbilitySystemComponent
extends Node
## Hub stats + abilities/effects. Réplication via StateSynchronizer + AttributesMirror.
## Serveur: met à jour les attributs, marque dirty sur le Synchronizer.
## Client : reçoit les deltas -> Mirror met à jour ses props dynamiques.

@export var synchronizer: StateSynchronizer
@export var mirror: AttributesMirror           # doit exister dans la scène (enfant recommandé, nom "AttributesMirror")

var _val: Dictionary[StringName, float] = {}   # current
var _max: Dictionary[StringName, float] = {}   # max

signal attribute_changed(attr: StringName, value: float, max_value: float, source: StringName)



static func _val_path(attr: StringName) -> String:
	return "AbilitySystemComponent/AttributesMirror:%s" % String(attr)

static func _max_path(attr: StringName) -> String:
	return "AbilitySystemComponent/AttributesMirror:%s_max" % String(attr)


func _ready() -> void:
	pass





# -------------------- Public API (serveur) ------------------------------------

func ensure_attr(attr: StringName, start_value: float, start_max: float) -> void:
	if not _max.has(attr):
		_max[attr] = start_max
	if not _val.has(attr):
		_val[attr] = clamp(start_value, -INF, start_max)
	mirror.register_attr(attr)
	# Seed local mirror (utile pour capture_baseline côté serveur)
	mirror.set_pair(attr, _val[attr], _max[attr])
	# Enregistre des pid pour ces chemins si nécessaire (facultatif, mark_* le fera au besoin).
	#var base := "AttributesMirror:" + String(attr)
	#PathRegistry.register_field(base,        PathRegistry.WIRE_F32)
	PathRegistry.register_field(_val_path(attr), PathRegistry.WIRE_F32)
	PathRegistry.register_field(_max_path(attr), PathRegistry.WIRE_F32)
	#PathRegistry.register_field(base + "_max", PathRegistry.WIRE_F32)
	
	synchronizer.set_by_path(_val_path(attr), start_value)
	synchronizer.set_by_path(_max_path(attr), start_max)


func set_max_server(attr: StringName, new_max: float, clamp_current: bool = true, source: StringName = &"") -> void:
	assert(multiplayer.is_server())
	ensure_attr(attr, _val.get(attr, 0.0), new_max)
	_max[attr] = new_max
	if clamp_current:
		_val[attr] = clamp(_val[attr], -INF, new_max)
	# Mirror + replication (2 champs)
	_mirror_and_mark(attr, _val[attr], _max[attr], true)
	emit_signal(&"attribute_changed", attr, _val[attr], _max[attr], source)

func set_value_server(attr: StringName, new_value: float, source: StringName = &"") -> void:
	assert(multiplayer.is_server())
	ensure_attr(attr, new_value, _max.get(attr, 0.0))
	_val[attr] = clamp(new_value, -INF, _max[attr])
	_mirror_and_mark(attr, _val[attr], _max[attr], true)
	emit_signal(&"attribute_changed", attr, _val[attr], _max[attr], source)

func add_delta_server(attr: StringName, delta: float, source: StringName = &"") -> void:
	assert(multiplayer.is_server())
	ensure_attr(attr, _val.get(attr, 0.0), _max.get(attr, 0.0))
	_val[attr] = clamp(_val[attr] + delta, -INF, _max[attr])
	_mirror_and_mark(attr, _val[attr], _max[attr], true)
	emit_signal(&"attribute_changed", attr, _val[attr], _max[attr], source)

# -------------------- Query (client/serveur) ----------------------------------

func get_value(attr: StringName) -> float:
	return _val.get(attr, mirror.get_value(attr))

func get_max(attr: StringName) -> float:
	return _max.get(attr, mirror.get_max(attr))

# -------------------- Internals ----------------------------------------------

func _mirror_and_mark(attr: StringName, v: float, m: float, only_if_changed: bool) -> void:
	# Met à jour le Mirror local (important pour StateSynchronizer.capture_baseline côté serveur)
	mirror.set_pair(attr, v, m)
	if synchronizer == null:
		return
	# Marque dirty deux NodePaths: "AttributesMirror:<attr>" et "AttributesMirror:<attr>_max"
	var p_val := NodePath("AttributesMirror:" + String(attr))
	var p_max := NodePath("AttributesMirror:" + String(attr) + "_max")
	synchronizer.mark_dirty_by_path(p_val, v, only_if_changed)
	synchronizer.mark_dirty_by_path(p_max, m, only_if_changed)
