class_name WeaponBehavior
extends EquipBehavior


## Scene weapon, abilities and logic are stored in it 
@export var scene: PackedScene = preload("res://source/common/gameplay/items/weapons/weapon.tscn")


@warning_ignore("unused_parameter")
func on_equip(character: Character, item: Item) -> void:
	super.on_equip(character, item)
	character.equip_weapon(scene)


@warning_ignore("unused_parameter")
func on_unequip(character: Character, item: Item) -> void:
	super.on_unequip(character, item)
	character.unequip_weapon(scene)
