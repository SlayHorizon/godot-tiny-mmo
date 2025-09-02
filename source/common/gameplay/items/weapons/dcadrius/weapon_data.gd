@icon("res://assets/node_icons/color/icon_weapon.png")
class_name WeaponData
extends Resource

enum weapon_class {
	Sword,
	Dagger,
	Staff,
	Bow
}
@export_group("Visuals")
@export var weapon_sprite: Texture
@export var flip_sprite: bool = false
@export var origin_point: Vector2 = Vector2.ZERO
@export_group("Data")
@export var class_type: weapon_class = weapon_class.Sword
@export var animation_library: AnimationLibrary
