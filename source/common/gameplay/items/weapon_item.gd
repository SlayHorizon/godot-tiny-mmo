class_name WeaponItem
extends GearItem


@export var scene: PackedScene


func on_equip(character: Character) -> void:
	super.on_equip(character)
	var weapon: Weapon = scene.instantiate()
	weapon.character = character
	character.equipment_component._mounted[slot.key] = weapon
	character.right_hand_spot.add_child(weapon)


func on_unequip(character: Character) -> void:
	super.on_unequip(character)
