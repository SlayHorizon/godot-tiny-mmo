class_name ActivableDoor
extends StaticBody2D
## A door / gate. OPEN = collision off (pass through); CLOSED = collision on
## (blocks players). It's a plain node — RoomNode drives it: on the server it
## decides, and a dungeon.room push tells every client which doors to toggle (see
## RoomNode), so no prop baking / ids are needed. Uses the closing/opening anims.
##
## For a room seal, set starts_open = true: the party walks in, the room closes it
## behind them, and clearing the room opens it onward. (open_door() is kept as the
## bare "open" call the ground_button demo uses.)

## Start open (collision off) instead of the default closed gate.
@export var starts_open: bool = false

@onready var door_anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var door_collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	set_open(starts_open, false) # snap to the authored state, no animation


## Open (pass) or close (block). [param animate] false snaps without playing the
## transition (used on spawn). Collision is toggled deferred — safe to call mid-
## physics (a door closing as the fight starts).
func set_open(is_open: bool, animate: bool = true) -> void:
	door_collision.set_deferred(&"disabled", is_open)
	if animate:
		door_anim.play(&"opening" if is_open else &"closing")
	else:
		door_anim.play(&"open" if is_open else &"closed")


## Bare "open" — kept for the ground_button demo.
func open_door() -> void:
	set_open(true)
