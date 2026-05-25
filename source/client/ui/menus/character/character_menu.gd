extends Control
## Character window: Stats / Attributes / Jobs tabs. The Stats and Attributes panels
## self-drive (they fetch their own data); Jobs is a placeholder until jobs exist.


func _on_close_button_pressed() -> void:
	hide()
