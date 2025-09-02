class_name EquipmentComponent
extends Node

@export var _asc: AbilitySystemComponent
var _slots: Dictionary[StringName, EquipableItem] = {}

func _ready() -> void:
	pass


func equip(slot: StringName, item: EquipableItem) -> bool:
	if _slots.has(slot):
		_unequip_internal(slot)
	_slots[slot] = item
	item.on_equip(_asc)
	return true

func unequip(slot: StringName) -> void:
	if not _slots.has(slot):
		return
	_unequip_internal(slot)

func _unequip_internal(slot: StringName) -> void:
	var item: EquipableItem = _slots[slot]
	item.on_unequip(_asc)
	_slots.erase(slot)
