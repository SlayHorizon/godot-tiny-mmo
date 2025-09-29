extends Control


func _ready() -> void:
	if Events.local_player:
		$VBoxContainer/HBoxContainer/HSlider.value = Events.local_player.get_node(^"Camera2D").zoom.x


func _on_h_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return
	var h_slider: HSlider = $VBoxContainer/HBoxContainer/HSlider
	if Events.local_player:
		Events.local_player.get_node(^"Camera2D").zoom = Vector2.ONE * h_slider.value 
	
	Events.settings["zoom"] = h_slider.value


func _on_button_pressed() -> void:
	hide()
