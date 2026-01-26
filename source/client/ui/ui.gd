class_name UI
extends CanvasLayer


@onready var hud: Control = $HUD


func _ready() -> void:
	for child: Node in get_children():
		if child is Control:
			child.theme = BetterThemeDB.theme
