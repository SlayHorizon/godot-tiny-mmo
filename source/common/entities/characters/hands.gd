@tool
class_name Hand
extends Sprite2D

enum Status {
	IDLE,
	GRAB,
	PULL
}

enum Sides {
	LEFT,
	RIGHT
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

func _init() -> void:
	_update_hands()

func _update_hands() -> void:
	if status == Status.PULL:
		region_rect = Rect2(2 * 16, 1 * 16, SIZE, SIZE)
	else:
		region_rect = Rect2(side * 16, status * 16, SIZE, SIZE)
