extends Node
class_name AttributeComponent
## Generic (current,max) attribute replicated authoritatively through StateSynchronizer.
## Examples: health, mana, energy, shield...
##
## Server:
##  - Mutates current/max.
##  - Calls _ps_current/_ps_max.mark(...) to replicate.
##  - Emits `gameplay_event` (observed by the instance event bus).
##
## Client:
##  - Only visual feedback (UI/VFX). Converges to server values via StateSynchronizer.

signal gameplay_event(event: StringName, payload: Dictionary)

signal current_changed(new_value: float)
signal max_changed(new_value: float)

@export var state_synchronizer: StateSynchronizer

## Attribute semantic name (for events/payload)
@export var attribute_name: StringName = &"health"

## NodePaths relative to the entity root (same root as StateSynchronizer).
## Ex. ^"HealthComponent:health"  and  ^"HealthComponent:max_health"
@export var path_current: NodePath = ^"HealthComponent:health"
@export var path_max: NodePath = ^"HealthComponent:max_health"



var current: float = 10.0:
	set(value):
		current = value
		current_changed.emit(value)

var maximum: float = 10.0:
	set(value):
		maximum = maxf(value, 0.0)
		max_changed.emit(maximum)
		if multiplayer.is_server():
			_ps_max.mark(state_synchronizer, maximum, true)

var get_current_value_callback: Callable

# Internal sync helpers (pid cache per path)
var _ps_current: PropertySync
var _ps_max: PropertySync


func _enter_tree() -> void:
	# Observer discovery via group (let the InstanceEventBus connect fast).
	add_to_group("emit_events")


func _init() -> void:
	if not state_synchronizer:
		return
	var node_path: NodePath = state_synchronizer.get_path_to(self)
	#_ps_current = node_path + ^":current"
	#_ps_max = maximum + ":maximum"


func _ready() -> void:
	_ps_current = PropertySync.new(path_current)
	_ps_max = PropertySync.new(path_max)


# -------------------- Server-side API ----------------------------------------


func set_current_server(value: float) -> void:
	current = clampf(value, 0.0, maximum)


func add_delta_server(delta: float, reason: StringName = &"") -> void:
	var before: float = current
	var after: float = clampf(before + delta, 0.0, maximum)
	current = after

	# Optional semantic event for clients (e.g., "hit" when negative delta).
	if delta < 0.0:
		emit_signal(&"gameplay_event", &"hit", {
			"attr": attribute_name,
			"amount": -delta,
			"from": reason
		})


func set_max_server(value: float, clamp_current: bool = true) -> void:
	maximum = maxf(value, 0.0)
	if clamp_current:
		current = minf(current, maximum)
