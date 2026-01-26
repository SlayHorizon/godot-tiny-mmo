class_name EquipmentComponent
extends Node


@export var _asc: AbilitySystemComponent
@export var character: Character

var _slots: Dictionary[StringName, GearItem]
var _mounted: Dictionary[StringName, Weapon]

var mainhand_id: int:
	set = _set_mainhand_id
var offhand_id: int:
	set = _set_offhand_id
var mount_id: int:
	set = _set_mount_id


func _ready() -> void:
	pass

# Good / Bad Design ?
func _set_mainhand_id(id: int) -> void:
	mainhand_id = id
	load_and_equip_weapon(id)
func _set_offhand_id(id: int) -> void:
	offhand_id = id
	load_and_equip_weapon(id)
func _set_mount_id(id: int) -> void:
	mount_id = id
	load_and_equip_weapon(id)


func load_and_equip_weapon(weapon_id: int) -> bool:
	var weapon: WeaponItem = ContentRegistryHub.load_by_id(&"items", weapon_id) as WeaponItem
	if not weapon:
		return false
	equip(weapon.slot.key, weapon)
	return true


func equip(slot: StringName, item: Item) -> bool:
	if _slots.has(slot):
		unequip(slot)
	_slots[slot] = item
	item.on_equip(character)
	return true


func unequip(slot: StringName) -> void:
	var item: Item = _slots.get(slot, null)
	if item:
		item.on_unequip(character)
		_slots.erase(slot)
	var node: Node = _mounted.get(slot, null)
	if node:
		node.queue_free()
		_mounted.erase(slot)


func can_use(slot: StringName, index: int) -> bool:
	return _mounted.has(slot) and _mounted[slot].can_use_weapon(index)


func process_input(local_player: LocalPlayer) -> void:
	if _mounted.has(&"weapon"):
		_mounted[&"weapon"].process_input(local_player)
