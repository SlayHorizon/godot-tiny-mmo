# AbilitySystemComponent.gd
class_name AbilitySystemComponent
extends Node
## Stats hub + gameplay effects/abilities.
## Server: updates attributes, marks StateSynchronizer dirty.
## Client: receives deltas; AttributesMirror exposes dynamic properties.

# --- Dispel mask --------------------------------------------------------------

const DISPEL_MAGIC: int = 1
const DISPEL_PHYSICAL: int = 1 << 1
const DISPEL_POISON: int = 1 << 2
const DISPEL_CURSE: int = 1 << 3
const DISPEL_CC: int = 1 << 4
const DISPEL_BUFF: int = 1 << 5

# --- Exports ------------------------------------------------------------------

@export var synchronizer: StateSynchronizer
@export var mirror: AttributesMirror

# --- Attributes state ---------------------------------------------------------

var _val: Dictionary[StringName, float] = {}
var _max: Dictionary[StringName, float] = {}

signal attribute_changed(attr: StringName, value: float, max_value: float, source: StringName)
signal cue_requested(cue_name: StringName, data: Dictionary)

static func _val_path(attr: StringName) -> String:
	return "AbilitySystemComponent/AttributesMirror:%s" % String(attr)

static func _max_path(attr: StringName) -> String:
	return "AbilitySystemComponent/AttributesMirror:%s_max" % String(attr)

func _ready() -> void:
	pass

# --- Public API: attributes (server) ------------------------------------------

func ensure_attr(attr: StringName, start_value: float, start_max: float) -> void:
	if not _max.has(attr):
		_max[attr] = start_max
	if not _val.has(attr):
		_val[attr] = clamp(start_value, -INF, start_max)

	mirror.register_attr(attr)
	mirror.set_pair(attr, _val[attr], _max[attr])

	PathRegistry.register_field(_val_path(attr), PathRegistry.WIRE_F32)
	PathRegistry.register_field(_max_path(attr), PathRegistry.WIRE_F32)

	if synchronizer != null:
		synchronizer.set_by_path(_val_path(attr), _val[attr])
		synchronizer.set_by_path(_max_path(attr), _max[attr])

func set_max_server(attr: StringName, new_max: float, clamp_current: bool = true, source: StringName = &"") -> void:
	assert(multiplayer.is_server())
	ensure_attr(attr, _val.get(attr, 0.0), new_max)
	_max[attr] = new_max
	if clamp_current:
		_val[attr] = clamp(_val[attr], -INF, new_max)
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

# --- Query (client/server) ----------------------------------------------------

func get_value(attr: StringName) -> float:
	if _val.has(attr):
		return _val[attr]
	return mirror.get_value(attr)

func get_max(attr: StringName) -> float:
	if _max.has(attr):
		return _max[attr]
	return mirror.get_max(attr)

# --- Internals: mirror + replication -----------------------------------------

func _mirror_and_mark(attr: StringName, v: float, m: float, only_if_changed: bool) -> void:
	mirror.set_pair(attr, v, m)
	if synchronizer == null:
		return
	#var p_val: NodePath = NodePath("AttributesMirror:" + String(attr))
	#var p_max: NodePath = NodePath("AttributesMirror:" + String(attr) + "_max")
	
	var p_val: NodePath = NodePath(_val_path(attr))
	var p_max: NodePath = NodePath(_max_path(attr))
	
	synchronizer.mark_dirty_by_path(p_val, v, only_if_changed)
	synchronizer.mark_dirty_by_path(p_max, m, only_if_changed)

# === Event bus ================================================================

class Listener:
	var tag: StringName
	var priority: int
	var cb: Callable
	var owner_id: int

# event -> (tag -> Array[Listener])
var _subs: Dictionary = {}

# owner_id -> Array[[event, tag, Listener]]
var _by_owner: Dictionary = {}


func subscribe(event: StringName, tag: StringName, priority: int, cb: Callable, owner_id: int) -> void:
	var per_event: Dictionary = _subs.get(event, {})
	var per_tag: Array = per_event.get(tag, [])

	var l: Listener = Listener.new()
	l.tag = tag
	l.priority = priority
	l.cb = cb
	l.owner_id = owner_id

	per_tag.append(l)
	# pas de types dans le comparateur pour éviter le clash avec un Array non-typé
	per_tag.sort_custom(func(a, b): return a.priority < b.priority)

	per_event[tag] = per_tag
	_subs[event] = per_event

	var lst: Array = _by_owner.get(owner_id, [])
	lst.append([event, tag, l])
	_by_owner[owner_id] = lst


func unsubscribe_all(owner_id: int) -> void:
	var lst: Array = _by_owner.get(owner_id, [])
	for trip in lst:
		var event: StringName = trip[0]
		var tag: StringName = trip[1]
		var l: Listener = trip[2]

		var per_event: Dictionary = _subs.get(event, {})
		var per_tag: Array = per_event.get(tag, [])
		per_tag.erase(l)
		per_event[tag] = per_tag
		_subs[event] = per_event

	_by_owner.erase(owner_id)


func _emit_event(event: StringName, ev: GameplayEvent) -> void:
	var per_event: Dictionary = _subs.get(event, {})

	# bucket = listeners wildcard + listeners par tag présent dans le spec
	var bucket: Array = []
	var base: Array = per_event.get(&"", [])
	if base.size() > 0:
		bucket.append_array(base)

	for t in ev.spec.tags:
		var arr: Array = per_event.get(StringName(t), [])
		if arr.size() > 0:
			bucket.append_array(arr)

	# boucle sans typer la variable d’itération pour éviter l’erreur de membre
	for i in range(bucket.size()):
		if ev.canceled:
			break
		var l: Listener = bucket[i]
		l.cb.call(ev, self)


# === Gameplay effects lifecycle ==============================================


@export var damage_model: DamageModelResource

var _active_effects: Array[GameplayEffect] = []
var _effects_clock: float = 0.0

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_effects_clock += delta

	# Tick and expire
	var to_remove: Array = []
	for e in _active_effects:
		if e.duration > 0.0 and e._expires_at >= 0.0 and _effects_clock >= e._expires_at:
			to_remove.append(e)
			continue
		if e.period > 0.0 and e._next_tick_at >= 0.0 and _effects_clock >= e._next_tick_at:
			e.on_tick(self)
			e._next_tick_at += e.period
	for e2 in to_remove:
		e2.on_removed(self)
		_active_effects.erase(e2)

func add_effect(eff: GameplayEffect, source: AbilitySystemComponent = null) -> void:
	# Stacking/refresh
	for existing in _active_effects:
		if existing.name_id == eff.name_id:
			if existing.stacks_max > existing._stacks:
				existing._stacks += 1
			# refresh duration
			if eff.duration > 0.0:
				existing._expires_at = _effects_clock + eff.duration
			return
	
	_active_effects.append(eff)
	eff._source = source
	if eff.duration > 0.0:
		eff._expires_at = _effects_clock + eff.duration
	if eff.period > 0.0:
		var start_delay: float = eff.first_tick_delay if eff.first_tick_delay > 0.0 else eff.period
		eff._next_tick_at = _effects_clock + start_delay
	eff.on_added(self)

func remove_effect_by_name(id: StringName) -> bool:
	for effect: GameplayEffect in _active_effects:
		if effect.name_id == id:
			effect.on_removed(self)
			_active_effects.erase(effect)
			return true
	return false

func dispel(mask: int, max_count: int = 999, only_debuffs: bool = true, tag_filter: StringName = StringName("")) -> int:
	var removed: int = 0
	for e in _active_effects.duplicate():
		var ge: GameplayEffect = e
		if only_debuffs and not ge.is_debuff:
			continue
		if tag_filter != StringName("") and not ge.tags.has(String(tag_filter)):
			continue
		if (ge.dispel_mask & mask) == 0:
			continue
		ge.on_removed(self)
		_active_effects.erase(ge)
		removed += 1
		if removed >= max_count:
			break
	return removed

# === Spec application pipeline ===============================================

func apply_spec_server(spec: EffectSpec, source: AbilitySystemComponent = null) -> void:
	assert(multiplayer.is_server())

	for key_any in spec.magnitudes.keys():
		var key: StringName = key_any
		var amt_raw: float = float(spec.magnitudes[key])
		if amt_raw == 0.0:
			continue

		var ev: GameplayEvent = GameplayEvent.new()
		ev.spec = spec
		ev.source = source
		ev.target = self
		ev.amount = amt_raw
		ev.canceled = false

		_emit_event(&"OnSpecGate", ev)
		if ev.canceled:
			continue

		_emit_event(&"OnSpecPreSource", ev)
		if ev.canceled:
			continue

		_emit_event(&"OnSpecPreTarget", ev)
		if ev.canceled:
			continue

		_emit_event(&"OnSpecMitigation", ev)
		if ev.canceled:
			continue

		var key_str: String = String(key)
		if key_str == "damage":
			_apply_damage_pools(ev)
		elif key_str == "heal":
			_apply_heal_pools(ev)
		else:
			_emit_event(&"OnApplyCustom", ev)

		_emit_event(&"OnSpecPostApply", ev)

# --- Spec application pipeline (swap pool apply calls) -----------------------

func _apply_damage_pools(ev: GameplayEvent) -> void:
	if damage_model != null:
		damage_model.apply_damage(self, ev.amount, ev.spec, ev.source)
		return
	# fallback
	var remain: float = ev.amount
	if not ev.spec.ignore_layers.has("Armor"):
		var armor: float = get_value(&"armor")
		remain = remain * (1.0 - _armor_formula(armor))
	if remain > 0.0 and not ev.spec.ignore_layers.has("Shield"):
		var sh: float = get_value(&"shield")
		var used: float = min(sh, remain)
		if used > 0.0:
			set_value_server(&"shield", sh - used)
			remain -= used
	if remain > 0.0:
		var hp: float = get_value(&"health")
		set_value_server(&"health", hp - remain)

func _apply_heal_pools(ev: GameplayEvent) -> void:
	if damage_model != null:
		damage_model.apply_heal(self, ev.amount, ev.spec, ev.source)
		return
	# fallback
	var hp: float = get_value(&"health")
	var mx: float = get_max(&"health")
	var add: float = ev.amount
	var new_hp: float = min(mx, hp + add)
	set_value_server(&"health", new_hp)
	var overflow: float = max(0.0, (hp + add) - mx)
	if overflow > 0.0 and not ev.spec.ignore_layers.has("Shield"):
		var sh: float = get_value(&"shield")
		set_value_server(&"shield", sh + overflow)

func _armor_formula(armor: float) -> float:
	return armor / (abs(armor) + 100.0)
