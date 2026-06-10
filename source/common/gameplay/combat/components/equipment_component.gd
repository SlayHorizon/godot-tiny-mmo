class_name EquipmentComponent
extends Node


signal equipment_changed(
	slot: StringName,
	item_id: int
)


@export var character: Character

@export var synchronizer: StateSynchronizer


var slots: EquipmentSlots = EquipmentSlots.new()

var equipped_items: Dictionary[StringName, GearItem]

#Note to myself because a weapon may spawn main weapon, offhand, trail vfx, aura mount etc.
# This format may be more scalable
#Later mounted_nodes: Dictionary[StringName, Array[Node]]
var mounted_nodes: Dictionary[StringName, Node]


func _ready() -> void:
	slots.slot_changed.connect(_on_slot_changed)


func equip_item(item_id: int) -> bool:
	var item: GearItem = ContentRegistryHub.load_by_id(&"items", item_id) as GearItem
	if item and item.can_equip(character):
		synchronizer.set_by_path(slot_path(item.slot.key), item_id)
		return true
	return false


func unequip(slot: StringName) -> void:
	synchronizer.set_by_path(slot_path(slot), 0)


func can_use(slot: StringName, index: int, released: bool = false) -> bool:
	var mounted: Weapon = mounted_nodes.get(slot, null)

	if mounted and mounted.has_method("can_use_weapon"):
		return mounted.can_use_weapon(index, released)
	return false


func process_input(local_player: LocalPlayer) -> void:
	var mounted: Weapon = mounted_nodes.get(&"weapon", null)

	if mounted and mounted.has_method("process_input"):
		mounted.process_input(local_player)


func _on_slot_changed(slot: StringName, item_id: int) -> void:
	_clear_slot(slot)

	if item_id == 0:
		equipment_changed.emit(slot, 0)
		return
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if not item:
		return
	
	equipped_items[slot] = item
	item.equip(character)
	equipment_changed.emit(slot,  item_id)


func _clear_slot(slot: StringName) -> void:
	var item: Item = equipped_items.get(slot, null)
	
	if item:
		item.unequip(character)
	equipped_items.erase(slot)


static func slot_path(slot: StringName) -> String:
	return "EquipmentComponent:slots:%s" % slot


class EquipmentSlots extends RefCounted:
	signal slot_changed(slot: StringName, item_id: int)

	var values: Dictionary[StringName, int]


	func _get(property: StringName) -> Variant:
		return values.get(property, 0)


	func _set(property: StringName, value: Variant) -> bool:
		if typeof(value) != TYPE_INT:
			return false

		values[property] = value

		slot_changed.emit(property, value)

		return true
