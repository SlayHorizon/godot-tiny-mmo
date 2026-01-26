class_name WeaponItem
extends GearItem


@export var scene: PackedScene
@export var second_hand: PackedScene


func on_equip(character: Character) -> void:
	super.on_equip(character)
	var weapon: Weapon = scene.instantiate()
	weapon.character = character
	character.equipment_component._mounted[slot.key] = weapon
	character.right_hand_spot.add_child(weapon)
	if second_hand:
		var seond_hand_weapon: Weapon = second_hand.instantiate()
		seond_hand_weapon.character = character
		character.left_hand_spot.add_child(seond_hand_weapon)
	else:
		if character.left_hand_spot.get_child_count():
			character.left_hand_spot.remove_child(character.left_hand_spot.get_child(0))


func on_unequip(character: Character) -> void:
	super.on_unequip(character)
