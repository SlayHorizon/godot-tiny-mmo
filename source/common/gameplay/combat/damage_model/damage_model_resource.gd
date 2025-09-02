# DamageModelResource.gd
class_name DamageModelResource
extends Resource

@export var layers_order: PackedStringArray = ["Armor", "Shield", "Health"]
@export var armor_k: float = 100.0
@export var overheal_to_shield: bool = true


func apply_damage(target: AbilitySystemComponent, amount: float, spec: EffectSpec, source: AbilitySystemComponent) -> void:
	var remain: float = amount

	if not spec.ignore_layers.has("Armor") and layers_order.has("Armor"):
		var armor: float = target.get_value(&"armor")
		var pen_flat: float = float(spec.meta.get("pen_flat", 0.0))
		var pen_pct: float = float(spec.meta.get("pen_pct", 0.0))
		var eff_armor: float = max(0.0, armor * (1.0 - pen_pct) - pen_flat)
		var dr: float = eff_armor / (abs(eff_armor) + armor_k)
		remain = remain * (1.0 - dr)

	if remain <= 0.0:
		return

	if not spec.ignore_layers.has("Shield") and layers_order.has("Shield"):
		var sh: float = target.get_value(&"shield")
		var used: float = min(sh, remain)
		if used > 0.0:
			target.set_value_server(&"shield", sh - used)
			remain -= used

	if remain > 0.0 and layers_order.has("Health"):
		var hp: float = target.get_value(&"health")
		target.set_value_server(&"health", hp - remain)


func apply_heal(target: AbilitySystemComponent, amount: float, spec: EffectSpec, source: AbilitySystemComponent) -> void:
	var hp: float = target.get_value(&"health")
	var mx: float = target.get_max(&"health")
	var new_hp: float = min(mx, hp + amount)
	target.set_value_server(&"health", new_hp)

	if overheal_to_shield:
		var overflow: float = max(0.0, (hp + amount) - mx)
		if overflow > 0.0 and not spec.ignore_layers.has("Shield") and layers_order.has("Shield"):
			var sh: float = target.get_value(&"shield")
			target.set_value_server(&"shield", sh + overflow)
