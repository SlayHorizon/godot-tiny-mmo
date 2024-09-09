extends CanvasLayer

const HUD = preload("res://source/client/ui/hud/hud.tscn")

func _ready() -> void:
	var login_menu: LoginMenu = $LoginMenu
	await login_menu.connection_succeed
	login_menu.queue_free()
	add_child(HUD.instantiate())
