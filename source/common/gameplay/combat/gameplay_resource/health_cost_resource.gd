# HealthCostResource.gd
class_name HealthCostResource
extends GameplayResource

@export var allow_self_kill: bool = false

func _init() -> void:
	id = &"hp_cost"

func setup(_asc: AbilitySystemComponent, _base_stats: Dictionary) -> void:
	# nothing to ensure: uses ASC.health pool
	pass

func can_pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, _ctx: Dictionary) -> bool:
	if cost_tag != &"hp":
		return false
	var hp: float = asc.get_value(&"health")
	return allow_self_kill or (hp - amount) > 0.0

func pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, _ctx: Dictionary) -> void:
	if cost_tag != &"hp":
		return
	asc.add_delta_server(&"health", -amount)

func get_ui_snapshot(_asc: AbilitySystemComponent) -> Dictionary:
	return { "id": id, "value": 0.0, "max": 0.0, "hidden": true }
