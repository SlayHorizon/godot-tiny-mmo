extends Area2D


@export_enum("blue", "gold") var coin_type: String = "blue"

@onready var coin_anim: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	coin_anim.play(coin_type + "_coin")


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		self.body_entered.disconnect(self._on_body_entered)
		coin_anim.animation_finished.connect(self.queue_free)
		coin_anim.play(&"collected")
	
