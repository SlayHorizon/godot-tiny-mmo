@icon("res://assets/node_icons/blue/icon_grid.png")
class_name InteractionArea
extends Area2D
## Base class of all interactible areas. Can be a collectible, a warper, a teleporter etc.

signal player_entered_interaction_area(player: Player, interaction_area: InteractionArea)


func _init() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body = body as Player
		if not body.just_teleported:
			player_entered_interaction_area.emit(body, self)
