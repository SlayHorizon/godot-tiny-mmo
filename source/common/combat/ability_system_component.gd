# AbilitySystemComponent.gd
class_name AbilitySystemComponent
extends Node
## Hub stats + abilities/effects. Réplication via StateSynchronizer + AttributesMirror.
## Serveur: met à jour les attributs, marque dirty sur le Synchronizer.
## Client : reçoit les deltas -> Mirror met à jour ses props dynamiques.

const DISPEL_MAGIC := 1
const DISPEL_PHYSICAL := 1 << 1
const DISPEL_POISON := 1 << 2
const DISPEL_CURSE := 1 << 3
const DISPEL_CC := 1 << 4
const DISPEL_BUFF := 1 << 5


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


# AbilitySystemComponent.gd (extraits ajoutés)

signal cue_requested(cue_name: StringName, data: Dictionary)   # pour VFX/SFX (replicables via ton manager)

# --- Event bus minimal --------------------------------------------------------
class Listener:
	var tag: StringName
	var priority: int
	var cb: Callable
	var owner_id: int

var _subs := {}    # event:StringName -> (tag:StringName -> Array[Listener])
var _by_owner := {} # owner_id -> Array[[event, tag, Listener]]

func subscribe(event: StringName, tag: StringName, priority: int, cb: Callable, owner_id: int) -> void:
	var per_event: Dictionary = _subs.get(event, {})
	var per_tag: Array = per_event.get(tag, [])
	var l := Listener.new()
	l.tag = tag; l.priority = priority; l.cb = cb; l.owner_id = owner_id
	per_tag.append(l)
	# tri par priorité (plus petit d’abord)
	per_tag.sort_custom(func(a, b): return a.priority < b.priority)
	per_event[tag] = per_tag
	_subs[event] = per_event
	var list: Array = _by_owner.get(owner_id, [])
	list.append([event, tag, l])
	_by_owner[owner_id] = list

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
	# listeners wildcard + listeners par tag présent dans le spec
	var per_event: Dictionary = _subs.get(event, {})
	var bucket: Array = per_event.get(&"", []).duplicate()
	for t in ev.spec.tags:
		var arr: Array = per_event.get(StringName(t), [])
		if arr.size() > 0:
			bucket.append_array(arr)
	# déjà trié à l’insertion ; si besoin re-trie ici
	for l: Listener in bucket:
		if ev.canceled:
			break
		l.cb.call(ev, self)

# --- Pipeline d’application ---------------------------------------------------
func apply_spec_server(spec: EffectSpec, source: AbilitySystemComponent = null) -> void:
	assert(multiplayer.is_server())

	# 1) Gate (block, “ignore”, etc.)
	for key: StringName in spec.magnitudes:
		var amt := float(spec.magnitudes[key])
		if amt == 0.0:
			continue
		var ev := GameplayEvent.new()
		ev.spec = spec
		ev.source = source
		ev.target = self
		ev.amount = amt

		_emit_event(&"OnSpecGate", ev)
		if ev.canceled:
			continue

		# 2) PreSource (crits, modifs côté source)
		_emit_event(&"OnSpecPreSource", ev)
		if ev.canceled:
			continue

		# 3) PreTarget (vulnérabilités, résistances spécifiques)
		_emit_event(&"OnSpecPreTarget", ev)
		if ev.canceled:
			continue

		# 4) Mitigation (modèle couches data-driven ou listener)
		_emit_event(&"OnSpecMitigation", ev)
		if ev.canceled:
			continue

		# 5) Application concrète (par type de magnitude)
		match String(key):
			"damage":
				_apply_damage_pools(ev)  # voir ci-dessous (layers simples)
			"heal":
				_apply_heal_pools(ev)
			_:
				# autres types (slow, resource gain…), à ta convenance via listeners
				_emit_event(&"OnApplyCustom", ev)

		# 6) Post (lifesteal, on-hit, procs…)
		_emit_event(&"OnSpecPostApply", ev)

func _apply_damage_pools(ev: GameplayEvent) -> void:
	# Exemple “Armor -> Shield -> Health” data-driven light
	var remain := ev.amount
	if not ev.spec.ignore_layers.has("Armor"):
		var armor := get_value(&"armor")
		remain = remain * (1.0 - _armor_formula(armor))   # ex: DR = armor/(armor+100)
	# shield
	if remain > 0.0 and not ev.spec.ignore_layers.has("Shield"):
		var sh := get_value(&"shield")
		var used: float = min(sh, remain)
		if used > 0.0:
			set_value_server(&"shield", sh - used)
			remain -= used
	# health
	if remain > 0.0:
		var hp := get_value(&"health")
		set_value_server(&"health", hp - remain)

func _apply_heal_pools(ev: GameplayEvent) -> void:
	var hp := get_value(&"health")
	var mx := get_max(&"health")
	var add := ev.amount
	var over: float = max(0.0, (hp + add) - mx)
	set_value_server(&"health", min(mx, hp + add))
	# surplus vers shield si tu veux (optionnel)
	if over > 0.0:
		var sh := get_value(&"shield")
		set_value_server(&"shield", sh + over)

func _armor_formula(armor: float) -> float:
	return armor / (abs(armor) + 100.0)   # placeholder ; remplace par ta ressource “DamageModel”


# AbilitySystemComponent.gd (ajouts)
var _active_effects: Array = []

func add_effect(eff: GameplayEffect) -> void:
	_active_effects.append(eff)
	eff.on_added(self)

func remove_effect_by_name(id: StringName) -> void:
	for i in range(_active_effects.size()):
		var e: GameplayEffect = _active_effects[i]
		if e.name_id == id:
			e.on_removed(self)
			_active_effects.remove_at(i)
			return


# AbilitySystemComponent.gd (ajoute)
func dispel(mask: int, max_count: int = 999, only_debuffs: bool = true, tag_filter: StringName = StringName("")) -> int:
	var removed := 0
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
