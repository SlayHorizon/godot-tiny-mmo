@tool
@icon("res://assets/node_icons/color/icon_weapon.png")
class_name Weapon
extends Node2D

enum Materials {
	WOOD,
	BONE,
}

enum Types {
	SWORD,
	HAMMER,
	KNIFE,
	AXE,
	SPEAR,
	MAGE_STAFF,
}

@export var _material: Materials = Materials.BONE:
	set = _set_material

@export var type: Types = Types.SWORD:
	set = _set_type

@onready var sprite: Sprite2D = $Sprite2D

func _set_material(new_material: Materials) -> void:
	match new_material:
		Materials.BONE:
			sprite.texture = preload("res://assets/sprites/items/weapons/bone/bone.png")
		Materials.WOOD:
			sprite.texture = preload("res://assets/sprites/items/weapons/wood/wood.png")
	_material = new_material

func _set_type(new_type: Types) -> void:
	type = new_type
	if not sprite:
		return
	match new_type:
		Types.SWORD:
			sprite.region_rect = Rect2(0, 0, 16, 48)
		Types.HAMMER:
			sprite.region_rect = Rect2(16, 16, 16, 32)
		Types.KNIFE:
			sprite.region_rect = Rect2(32, 16, 16, 32)
