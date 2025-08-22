# GameplayEvent.gd (ou classe interne ASC)
class_name GameplayEvent
extends RefCounted

var spec: EffectSpec
var source: AbilitySystemComponent
var target: AbilitySystemComponent
var amount: float = 0.0
var canceled: bool = false

func mod_mul(f: float) -> void: amount *= f
func mod_add(x: float) -> void: amount += x
func cancel() -> void: canceled = true
