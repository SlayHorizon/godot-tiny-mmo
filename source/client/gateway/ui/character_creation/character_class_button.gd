@tool
class_name CharacterClassButton
extends Button


@export var character_class: CharacterResource:
	set(value):
		if not value:
			return
		character_class = value
		if not is_node_ready():
			await ready
		update_button()

@onready var label: Label = $Label
@onready var animated_sprite_2d: AnimatedSprite2D = $CenterContainer/Control/AnimatedSprite2D


func _ready() -> void:
	if not character_class:
		return
	update_button()


func update_button() -> void:
	label.text = character_class.character_name
	animated_sprite_2d.sprite_frames = character_class.character_sprite
