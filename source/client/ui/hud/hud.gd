class_name HUD
extends CanvasLayer


var last_opened_interface: Control
var guild_menu: Control 

func _ready() -> void:
	pass


func _on_item_slot_button_1_pressed(extra_arg_0: String) -> void:
	Events.item_icon_pressed.emit(extra_arg_0)


func _on_item_slot_button_2_pressed(extra_arg_0: String) -> void:
	Events.item_icon_pressed.emit(extra_arg_0)


func _on_guild_button_pressed() -> void:
	if not guild_menu:
		guild_menu = load("res://source/client/ui/guild/guild_menu.tscn").instantiate()
		add_sibling(guild_menu)
	guild_menu.show()
