class_name WeaponItem
extends GearItem


@export var scene: PackedScene
@export var mount_point: StringName = &"weapon_main"


func on_equip(character: Character) -> void:
	super.on_equip(character)
	character.equip_weapon(mount_point, scene)


func on_unequip(character: Character) -> void:
	super.on_unequip(character)
	character.unequip_weapon(mount_point)
