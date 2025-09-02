# GameplayResource.gd
class_name GameplayResource
extends Resource
## Pluggable resource module (Mana, Energy, Fury, HealthCost, Heat, ...)


# e.g. "mana", "energy", "fury", "heat", "hp_cost"
@export var id: StringName

## Client can read it if needed for progress bar color for example.
@export var ui_color: Color = Color(0.2, 0.4, 1.0, 1.0)
@export var show_bar: bool = true


func setup(asc: AbilitySystemComponent, base_stats: Dictionary) -> void:
	# Called once on spawn. Register/ensure needed attributes on ASC.
	pass


func teardown(asc: AbilitySystemComponent) -> void:
	# Clean subscriptions/state
	pass


func tick_server(asc: AbilitySystemComponent, dt: float) -> void:
	# Server-side regen/decay/overheat logic
	pass


func can_pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, ctx: Dictionary) -> bool:
	# Return true if this module can pay for cost_tag
	return false


func pay(asc: AbilitySystemComponent, cost_tag: StringName, amount: float, ctx: Dictionary) -> void:
	# Deduct or apply the cost
	pass


func get_ui_snapshot(asc: AbilitySystemComponent) -> Dictionary:
	# Optional: return { "id": id, "value": float, "max": float }
	return {}
