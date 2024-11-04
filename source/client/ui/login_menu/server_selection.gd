# Fast script for prototyping
extends Control


var selected_server := "Witwitnds"


func _on_server_confirm_button_pressed() -> void:
	pass


func _on_server_button_1_pressed() -> void:
	selected_server = "Sladida"


func _on_server_button_2_pressed() -> void:
	selected_server = "Witwitnds"
