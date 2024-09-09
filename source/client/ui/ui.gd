extends CanvasLayer

const CHAT_SCENE = preload("res://source/client/ui/chat/chat.tscn")

func _ready() -> void:
	var login_menu: LoginMenu = $LoginMenu
	await login_menu.connection_succeed
	login_menu.queue_free()
	add_child(CHAT_SCENE.instantiate())
