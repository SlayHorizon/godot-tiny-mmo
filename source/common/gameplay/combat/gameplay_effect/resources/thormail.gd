class_name ThornmailEffect
extends GameplayEffect

@export var reflect_ratio: float = 0.25

func on_added(asc: AbilitySystemComponent) -> void:
	_sub(asc, &"OnSpecPostApply", &"Damage", 50, &"_on_post")

func _on_post(ev: GameplayEvent, self_asc: AbilitySystemComponent) -> void:
	#print_debug(ev, self_asc)
	if ev.canceled or ev.amount <= 0.0:
		return
	if ev.spec.tags.has("Reflect"):
		return
	if ev.source == null:
		return
	
	var back: EffectSpec = EffectSpec.damage(ev.amount * reflect_ratio, ["Damage.Magic", "Reflect"])
	ev.source.apply_spec_server(back, self_asc)
