extends StaticBody2D


@export var door_id: int = 0

@onready var door_anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var door_collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	ClientEvents.open_door.connect(self._on_door_open)
	door_anim.play(&"closed")


func _on_door_open(_door_id: int) -> void:
	door_anim.play(&"opening")
	door_collision.disabled = true
