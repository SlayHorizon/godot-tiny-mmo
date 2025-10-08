extends Label


func _ready() -> void:
	if multiplayer.is_server():
		return
	get_parent().display_name_changed.connect(_on_display_name_changed)


func _on_display_name_changed(new_name: String) -> void:
	text = new_name
