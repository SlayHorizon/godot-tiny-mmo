extends Node


@export var element_name: String = "Fire"
@export_enum("Offensive", "Defensive", "Support") var element_type: String
@export var icon: Texture2D


func apply_passive(player: Player) -> void:
	pass


func use_element_ability(player: Player) -> void:
	pass
