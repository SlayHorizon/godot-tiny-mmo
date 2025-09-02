# EffectSpec.gd
class_name EffectSpec
extends Resource


@export var tags: PackedStringArray = []

var magnitudes: Dictionary[StringName, float] = {}
var ignore_layers: PackedStringArray = []
var meta: Dictionary = {}


static func damage(amount: float, tags: PackedStringArray = [], meta: Dictionary = {}) -> EffectSpec:
	var s: EffectSpec = EffectSpec.new()
	s.tags = tags
	s.magnitudes[StringName("damage")] = amount
	s.meta = meta
	return s


static func heal(amount: float, tags: PackedStringArray = [], meta: Dictionary = {}) -> EffectSpec:
	var s: EffectSpec = EffectSpec.new()
	s.tags = tags
	s.magnitudes[StringName("heal")] = amount
	s.meta = meta
	return s
