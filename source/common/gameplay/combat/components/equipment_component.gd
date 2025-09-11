class_name EquipmentComponent
extends Node


@export var _asc: AbilitySystemComponent
@export var character: Character

var _slots: Dictionary[StringName, GearItem] = {}


func _ready() -> void:
	pass


func equip(slot: StringName, item: GearItem) -> bool:
	if _slots.has(slot):
		_unequip_internal(slot)
	_slots[slot] = item
	item.on_equip(character)
	return true

func unequip(slot: StringName) -> void:
	if not _slots.has(slot):
		return
	_unequip_internal(slot)

func _unequip_internal(slot: StringName) -> void:
	var item: GearItem = _slots[slot]
	item.on_unequip(character)
	_slots.erase(slot)
