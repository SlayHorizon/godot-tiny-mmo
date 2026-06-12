class_name WeaponItem
extends GearItem


## Mastery category this weapon belongs to (&"sword", &"bow", &"wand",
## &"hammer"). Killing with it earns mastery xp for the category; empty = no
## mastery (tools, special-case weapons). See docs/mastery.md.
@export var category: StringName
## Max ability weight (= node tier) the special slot accepts — the gear half
## of the mastery system: higher-tier weapons channel heavier abilities.
@export_range(1, 3) var capacity: int = 1

@export var right_hand_scene: PackedScene

@export var left_hand_scene: PackedScene


func equip(character: Character) -> void:
	super.equip(character)

	if right_hand_scene:
		var right_hand_weapon: Weapon = right_hand_scene.instantiate()
		right_hand_weapon.character = character
		character.equipment_component.mounted_nodes[slot.key] = right_hand_weapon
		character.right_hand_spot.add_child(right_hand_weapon)
	
	if left_hand_scene:
		var left_hand_weapon: Weapon = left_hand_scene.instantiate()
		left_hand_weapon.character = character
		character.left_hand_spot.add_child(left_hand_weapon)
	else:
		if character.left_hand_spot.get_child_count():
			character.left_hand_spot.get_child(0).queue_free()
			#character.left_hand_spot.remove_child(character.left_hand_spot.get_child(0))


func unequip(character: Character) -> void:
	super.unequip(character)

	var weapon: Node = character.equipment_component.mounted_nodes.get(slot.key, null)
	if weapon:
		weapon.queue_free()
	character.equipment_component.mounted_nodes.erase(slot.key)
	for child in character.left_hand_spot.get_children():
		child.queue_free()
