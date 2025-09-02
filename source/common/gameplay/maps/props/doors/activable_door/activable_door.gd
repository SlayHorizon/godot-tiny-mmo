extends StaticBody2D


@export var door_id: int = 0

@onready var door_anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var door_collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	door_anim.play(&"closed")


func open_door() -> void:
	door_anim.play(&"opening")
	door_collision.disabled = true
