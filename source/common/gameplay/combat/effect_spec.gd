class_name EffectSpec
extends Resource


@export var tags: PackedStringArray = []

var magnitudes: Dictionary[StringName, float] = {}
var ignore_layers: PackedStringArray = []
var meta: Dictionary = {}


static func damage(amount: float, _tags: PackedStringArray = [], _meta: Dictionary = {}) -> EffectSpec:
	var s: EffectSpec = EffectSpec.new()
	s.tags = _tags
	s.magnitudes[StringName("damage")] = amount
	s.meta = _meta
	return s


static func heal(amount: float, _tags: PackedStringArray = [], _meta: Dictionary = {}) -> EffectSpec:
	var s: EffectSpec = EffectSpec.new()
	s.tags = _tags
	s.magnitudes[StringName("heal")] = amount
	s.meta = _meta
	return s
