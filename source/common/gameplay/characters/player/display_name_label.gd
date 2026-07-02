extends Label


func _ready() -> void:
	if multiplayer.is_server():
		return
	get_parent().display_name_changed.connect(_on_display_name_changed)


func _notification(what: int) -> void:
	# Long text grows the rect rightward from the fixed left edge, and the 0.2
	# scale pivots at the top-left corner — recenter on the parent every resize.
	if what == NOTIFICATION_RESIZED:
		position.x = -size.x * scale.x / 2.0


func _on_display_name_changed(new_name: String) -> void:
	text = new_name
