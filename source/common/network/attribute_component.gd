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

## Optional UI
@export var progress_bar: ProgressBar
@export var show_floating_numbers: bool = true

## Server-only behavior
@export var emit_zero_event_on_depletion: bool = true   # e.g., death for health

var current: float = 10.0:
	set(value):
		current = value
		_update_ui_current(value)
		current_changed.emit(value)
		if multiplayer.is_server():
			_ps_current.mark(state_synchronizer, value, true)
			if emit_zero_event_on_depletion and current <= 0.0:
				emit_signal(&"gameplay_event", &"attr_zero", { "attr": attribute_name })

var maximum: float = 10.0:
	set(value):
		maximum = maxf(value, 0.0)
		_update_ui_max(maximum)
		max_changed.emit(maximum)
		if multiplayer.is_server():
			_ps_max.mark(state_synchronizer, maximum, true)

# Internal sync helpers (pid cache per path)
var _ps_current: PropertySync
var _ps_max: PropertySync


func _enter_tree() -> void:
	# Observer discovery via group (let the InstanceEventBus connect fast).
	add_to_group("emit_events")


func _ready() -> void:
	_ps_current = PropertySync.new(path_current)
	_ps_max = PropertySync.new(path_max)

	if progress_bar:
		progress_bar.min_value = 0.0
		progress_bar.max_value = maximum
		progress_bar.value = current


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


# -------------------- Client-only feedback helpers ---------------------------


func rp_hit(payload: Dictionary) -> void:
	# Called by client event dispatcher (optional), e.g. floating text.
	if not show_floating_numbers:
		return
	var amount: float = float(payload.get("amount", 0.0))
	_show_floating_number(amount)


func rp_attr_zero(payload: Dictionary) -> void:
	# Generic "depleted" visual; can be overridden or routed elsewhere.
	# For health, your entity might implement rp_death() separately.
	pass


func _show_floating_number(amount: float) -> void:
	if not OS.has_feature("client"):
		return
	var label: Label = Label.new()
	label.text = str(int(round(amount)))
	label.top_level = true
	label.global_position = owner.global_position
	add_child(label)
	var tw: Tween = create_tween()
	tw.set_parallel()
	tw.tween_property(label, "modulate:a", 0.3, 0.7)
	tw.tween_property(label, "scale", Vector2.ONE, 0.3)
	tw.tween_property(label, "scale", Vector2(0.4, 0.4), 1.0).set_delay(0.6)
	tw.chain().tween_callback(label.queue_free)


# -------------------- UI update ----------------------------------------------


func _update_ui_current(value: float) -> void:
	if progress_bar:
		progress_bar.value = value


func _update_ui_max(value: float) -> void:
	if progress_bar:
		progress_bar.max_value = value
