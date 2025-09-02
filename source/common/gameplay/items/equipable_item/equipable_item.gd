class_name EquipableItem
extends Resource

@export var display_name: String = ""
@export var mods: Array[StatModifier] = []
@export var persistent_effect: GameplayEffect = null  # ex: ThornmailEffect

func on_equip(asc: AbilitySystemComponent) -> void:
	for m in mods:
		var mm: StatModifier = m
		asc.add_modifier(mm)
	if persistent_effect != null:
		asc.add_effect(persistent_effect)

func on_unequip(asc: AbilitySystemComponent) -> void:
	for m in mods:
		var mm: StatModifier = m
		asc.remove_modifier_by_id(mm.runtime_id)
	if persistent_effect != null:
		asc.remove_effect_by_name(persistent_effect.name_id)
