@tool
@icon("res://assets/node_icons/blue/icon_hand.png")
class_name Hand
extends Sprite2D

enum Sides {
	LEFT,
	RIGHT
}

enum Status {
	IDLE,
	GRAB,
	PULL
}

enum Types {
	HUMAN,
	BROWN,
	ORC,
	GOBLIN,
}

const SIZE := 16

@export var side: Sides = Sides.LEFT:
	set(new_side):
		side = new_side
		_update_hands()
		
@export var status: Status = Status.IDLE:
	set(new_status):
		status = new_status
		_update_hands()

@export var type: Types = Types.HUMAN:
	set = _set_type

@export var current_weapon: WeaponData:
	set = _set_weapon
	
func _set_weapon(new_data : WeaponData) -> void:
	current_weapon = new_data
	
	var weapon: Sprite2D = $Weapon
	if not new_data:
		weapon.texture = null
		return
		
	weapon.texture = new_data.weapon_sprite
	weapon.position = Vector2.ZERO
	weapon.offset = new_data.origin_point if side == Sides.RIGHT else Vector2(-new_data.origin_point.x, new_data.origin_point.y)
	weapon.flip_h = new_data.flip_sprite if side == Sides.RIGHT else not new_data.flip_sprite

func _init() -> void:
	_update_hands()

func _update_hands() -> void:
	if status == Status.PULL:
		region_rect = Rect2(2 * SIZE, 1 * SIZE, SIZE, SIZE)
	else:
		region_rect = Rect2(side * SIZE, status * SIZE, SIZE, SIZE)

func _set_type(new_type: Types) -> void:
	match new_type:
		Types.HUMAN:
			texture = preload("res://assets/sprites/items/weapons/hands/human_hands.png")
		Types.BROWN:
			texture = preload("res://assets/sprites/items/weapons/hands/brown_leather_gloves.png")
		Types.GOBLIN:
			texture = preload("res://assets/sprites/items/weapons/hands/goblin_hands.png")
		Types.ORC:
			texture = preload("res://assets/sprites/items/weapons/hands/orc_hands.png")
	type = new_type
