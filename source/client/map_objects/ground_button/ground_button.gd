extends Area2D


@export var activable_door: Array[Node2D]
@export var interaction_id: int = 0
@export var one_shot: bool = true

@onready var button_anim: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	button_anim.play(&"up")


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		if one_shot:
			body_entered.disconnect(_on_body_entered)
		button_anim.animation_finished.connect(_on_button_pressed)
		button_anim.play(&"pressed")


func _on_button_pressed():
	button_anim.animation_finished.disconnect(_on_button_pressed)
	for door: Node2D in activable_door:
		if door.has_method("open_door"):
			door.open_door()
