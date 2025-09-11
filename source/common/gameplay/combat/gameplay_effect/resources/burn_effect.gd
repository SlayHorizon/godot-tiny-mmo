class_name BurnDotEffect
extends GameplayEffect

@export var dps: float = 10.0


func on_tick(asc: AbilitySystemComponent) -> void:
	var amt: float = dps * max(0.0, period)
	var spec: EffectSpec = EffectSpec.damage(amt, ["Damage.True", "Periodic", "Burn"])
	asc.apply_spec_server(spec, _source)
