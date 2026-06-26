class_name EquipmentComponent
extends Node


## Pseudo-slots carrying the mastery-chosen special abilities ("abilities"
## registry ids, 0 = none). Synced exactly like gear slots so every machine —
## server, owner, remote clients replaying action echoes — mounts the SAME
## specials on the weapon. Only the server writes them (MasteryService.refresh).
const SPECIAL_SLOT: StringName = &"special_ability"
const SPECIAL_SLOT_2: StringName = &"special_ability_2"


signal equipment_changed(
	slot: StringName,
	item_id: int
)


@export var character: Character

@export var synchronizer: StateSynchronizer


var slots: EquipmentSlots = EquipmentSlots.new()

var equipped_items: Dictionary[StringName, Item]

#Note to myself because a weapon may spawn main weapon, offhand, trail vfx, aura mount etc.
# This format may be more scalable
#Later mounted_nodes: Dictionary[StringName, Array[Node]]
var mounted_nodes: Dictionary[StringName, Node]

## Last synced special-ability ids, kept so a weapon mounted AFTER the special
## pairs applied (baseline ordering isn't guaranteed) still picks them up.
var _special_ability_ids: Array[int] = [0, 0]


func _ready() -> void:
	slots.slot_changed.connect(_on_slot_changed)


func equip_item(item_id: int) -> bool:
	var item: GearItem = ContentRegistryHub.load_by_id(&"items", item_id) as GearItem
	if item and item.can_equip(character):
		synchronizer.set_by_path(slot_path(item.slot.key), item_id)
		return true
	return false


## Put ANY item in the HAND (the &"weapon" slot) — weapon, potion, material. Synced
## like every slot, so all clients mount it; the item's own equip() does the mounting.
## Validation (ownership, can_equip for gear) is the handler's job before this.
func set_hand(item_id: int) -> void:
	synchronizer.set_by_path(slot_path(&"weapon"), item_id)


func unequip(slot: StringName) -> void:
	synchronizer.set_by_path(slot_path(slot), 0)


## Server-side: publish the mastery special-ability ids; clients receive them
## through the regular state sync and remount via _on_slot_changed.
func set_special_abilities(ability_ids: Array[int]) -> void:
	var first: int = ability_ids[0] if ability_ids.size() > 0 else 0
	var second: int = ability_ids[1] if ability_ids.size() > 1 else 0
	if _special_ability_ids[0] != first:
		synchronizer.set_by_path(slot_path(SPECIAL_SLOT), first)
	if _special_ability_ids[1] != second:
		synchronizer.set_by_path(slot_path(SPECIAL_SLOT_2), second)


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
	# Not gear: the value is an ability id for one of the weapon's special slots.
	if slot == SPECIAL_SLOT or slot == SPECIAL_SLOT_2:
		_special_ability_ids[0 if slot == SPECIAL_SLOT else 1] = item_id
		_apply_special_to_mounted()
		# Emitted AFTER the remount so listeners (the HUD ability bar) read the
		# weapon's final abilities. Server-side listeners filter on &"weapon".
		equipment_changed.emit(slot, item_id)
		return

	_clear_slot(slot)

	if item_id == 0:
		equipment_changed.emit(slot, 0)
		return
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if not item:
		return

	equipped_items[slot] = item
	item.equip(character)
	if slot == &"weapon":
		_apply_special_to_mounted()
	equipment_changed.emit(slot,  item_id)


func _apply_special_to_mounted() -> void:
	var mounted: Weapon = mounted_nodes.get(&"weapon", null) as Weapon
	if mounted != null:
		mounted.mount_specials(_special_ability_ids)


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
