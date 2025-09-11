class_name PotionHealEffect
extends GameplayEffect


var percent_of_max: float = 0.10
var flat_heal: float = 5.0


func on_added(asc: AbilitySystemComponent) -> void:
	var max_hp: float = asc.get_max(&"health")
	var to_heal: float = flat_heal + percent_of_max * max(0.0, max_hp)
	
	asc.apply_spec_server(EffectSpec.heal(to_heal))
	
