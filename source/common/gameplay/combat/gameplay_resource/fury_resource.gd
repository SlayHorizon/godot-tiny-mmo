# FuryResource.gd
class_name FuryResource
extends GameplayResource

@export var max_fury: float = 100.0
@export var decay_per_second: float = 10.0
@export var build_tag: StringName = &"OnSpecPostApply"  # listen after applying damage
@export var build_amount_on_hit: float = 5.0

var _owner_sub_id: int = randi()

func _init() -> void:
	id = &"fury"

func setup(asc: AbilitySystemComponent, _base_stats: Dictionary) -> void:
	asc.ensure_attr(&"fury", 0.0, max_fury)
	asc.set_max_server(&"fury", max_fury, true)
	asc.set_value_server(&"fury", 0.0)
	# build on dealing damage
	asc.subscribe(&"OnSpecPostApply", &"Damage", 80, Callable(self, "_on_post_apply"), _owner_sub_id)

func teardown(asc: AbilitySystemComponent) -> void:
	asc.unsubscribe_all(_owner_sub_id)

func _on_post_apply(ev: GameplayEvent, self_asc: AbilitySystemComponent) -> void:
	# if self was the source of the damage, build fury
	if ev.source == self_asc and ev.amount > 0.0:
		var cur: float = self_asc.get_value(&"fury")
		var mx: float = self_asc.get_max(&"fury")
		self_asc.set_value_server(&"fury", min(mx, cur + build_amount_on_hit))

func tick_server(asc: AbilitySystemComponent, dt: float) -> void:
	var cur: float = asc.get_value(&"fury")
	if cur > 0.0 and decay_per_second > 0.0:
		asc.set_value_server(&"fury", max(0.0, cur - decay_per_second * dt))

func can_pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, _ctx: Dictionary) -> bool:
	if cost_tag != &"fury":
		return false
	return asc.get_value(&"fury") >= amount

func pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, _ctx: Dictionary) -> void:
	if cost_tag != &"fury":
		return
	asc.add_delta_server(&"fury", -amount)

func get_ui_snapshot(asc: AbilitySystemComponent) -> Dictionary:
	return {
		"id": id,
		"value": asc.get_value(&"fury"),
		"max": asc.get_max(&"fury"),
	}
