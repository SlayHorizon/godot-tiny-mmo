# ManaResource.gd
class_name ManaResource
extends GameplayResource

@export var regen_per_second: float = 2.5

func _init() -> void:
	id = &"mana"

func setup(asc: AbilitySystemComponent, base_stats: Dictionary) -> void:
	var mx: float = float(base_stats.get(&"mana_max", 0.0))
	var cur: float = float(base_stats.get(&"mana", mx))
	if mx > 0.0:
		asc.ensure_attr(&"mana", cur, mx)
		asc.set_max_server(&"mana", mx, true)
		asc.set_value_server(&"mana", cur)

func can_pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, _ctx: Dictionary) -> bool:
	if cost_tag != &"mana":
		return false
	return asc.get_value(&"mana") >= amount

func pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, _ctx: Dictionary) -> void:
	if cost_tag != &"mana":
		return
	asc.add_delta_server(&"mana", -amount)

func tick_server(asc: AbilitySystemComponent, dt: float) -> void:
	var mx: float = asc.get_max(&"mana")
	if mx <= 0.0:
		return
	var cur: float = asc.get_value(&"mana")
	if cur < mx:
		asc.set_value_server(&"mana", min(mx, cur + regen_per_second * dt))

func get_ui_snapshot(asc: AbilitySystemComponent) -> Dictionary:
	return {
		"id": id,
		"value": asc.get_value(&"mana"),
		"max": asc.get_max(&"mana"),
	}
