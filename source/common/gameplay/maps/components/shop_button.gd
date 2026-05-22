extends Button


@export var shop_id: StringName = &"default"


func _ready() -> void:
	if multiplayer.is_server():
		return
	pressed.connect(_on_shop_pressed)


func _on_shop_pressed() -> void:
	ClientState.open_menu_requested.emit(&"shop", shop_id)
	#hide()
