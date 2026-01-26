extends Control


func _ready() -> void:
	$VBoxContainer/HBoxContainer/HSlider.value = ClientState.settings.get_key(&"camera_zoom", 2)


func _on_h_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return
	var h_slider: HSlider = $VBoxContainer/HBoxContainer/HSlider
	if ClientState.local_player:
		ClientState.local_player.set_camera_zoom(h_slider.value * Vector2.ONE)
	
	ClientState.settings[&"camera_zoom"] = h_slider.value


func _on_button_pressed() -> void:
	hide()
