# EffectSpec.gd
class_name EffectSpec
extends RefCounted

var source_eid: int
# ex: ["Damage.Physical", "Projectile", "BasicAttack"]
var tags: PackedStringArray = []
# ou {"heal": x}, tu peux en mettre plusieurs
var magnitudes := {&"damage": 0.0}
# ex: {"pierce_count":2, "falloff":0.8, "pen_tier":1}
var meta := {}
# ex: ["Armor"]
var ignore_layers: PackedStringArray = []

# Helper to make damage "attack"
static func damage(src: int, amount: float, tags:=[], meta:={}) -> EffectSpec:
	var s := EffectSpec.new()
	s.source_eid = src
	s.tags = tags
	s.magnitudes[&"damage"] = amount
	s.meta = meta
	return s
