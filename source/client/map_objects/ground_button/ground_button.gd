extends Area2D


@export var interaction_id: int = 0
@export var one_shot: bool = true

@onready var button_anim: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	button_anim.play(&"up")


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		if one_shot:
			self.body_entered.disconnect(self._on_body_entered)
		button_anim.animation_finished.connect(self._on_button_pressed)
		button_anim.play(&"pressed")


func _on_button_pressed():
	button_anim.animation_finished.disconnect(self._on_button_pressed)
	ClientEvents.open_door.emit(interaction_id)
