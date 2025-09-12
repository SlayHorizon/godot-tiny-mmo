class_name HUD
extends CanvasLayer


var last_opened_interface: Control

var inventory: Control
var guild_menu: Control 
var player_profile: Control 

@onready var menu_overlay: Control = $MenuOverlay
@onready var close_button: Button = $MenuOverlay/VBoxContainer/CloseButton
@onready var sub_menu: CanvasLayer = $SubMenu


func _ready() -> void:
	pass


func _on_guild_button_pressed() -> void:
	if not guild_menu:
		guild_menu = load("res://source/client/ui/guild/guild_menu.tscn").instantiate()
		add_sibling(guild_menu)
	guild_menu.show()


func _on_menu_button_pressed() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(menu_overlay, ^"position:x", menu_overlay.position.x + menu_overlay.size.x, 0.0)
	tween.tween_callback(menu_overlay.show)
	tween.tween_property(menu_overlay, ^"position:x", 815.0, 0.3)
	if not close_button.pressed.is_connected(_on_overlay_menu_close_button_pressed):
		close_button.pressed.connect(_on_overlay_menu_close_button_pressed)


func _on_overlay_menu_close_button_pressed() -> void:
	menu_overlay.hide()


func _on_inventory_button_pressed() -> void:
	menu_overlay.hide()
	if not inventory:
		inventory = (load("res://source/client/ui/inventory/inventory.tscn") as PackedScene).instantiate()
		inventory.visibility_changed.connect(_on_submenu_visiblity_changed.bind(inventory))
		sub_menu.add_child(inventory)
	inventory.show()


func open_player_profile(player_id: int) -> void:
	if not player_profile:
		player_profile = load("res://source/client/ui/player_profile.tscn").instantiate()
		player_profile.visibility_changed.connect(_on_submenu_visiblity_changed.bind(player_profile))
		sub_menu.add_child(player_profile)
	player_profile.open_player_profile(player_id)


func _on_submenu_visiblity_changed(menu: Control) -> void:
	if menu.visible:
		hide()
	else:
		show()
