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


@onready var menu_overlay: Control = $MenuOverlay
@onready var close_button: Button = $MenuOverlay/VBoxContainer/CloseButton
@onready var sub_menu: CanvasLayer = $SubMenu


func _on_menu_button_pressed() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(menu_overlay, ^"position:x", menu_overlay.position.x + menu_overlay.size.x, 0.0)
	tween.tween_callback(menu_overlay.show)
	tween.tween_property(menu_overlay, ^"position:x", 815.0, 0.3)
	if not close_button.pressed.is_connected(_on_overlay_menu_close_button_pressed):
		close_button.pressed.connect(_on_overlay_menu_close_button_pressed)


func _on_overlay_menu_close_button_pressed() -> void:
	menu_overlay.hide()

var inventory: Control
func _on_inventory_button_pressed() -> void:
	menu_overlay.hide()
	if not inventory:
		inventory = (load("res://source/client/ui/inventory/inventory.tscn") as PackedScene).instantiate()
		inventory.visibility_changed.connect(_on_submenu_visiblity_changed.bind(inventory))
		sub_menu.add_child(inventory)
	inventory.show()


func _on_submenu_visiblity_changed(submenu: Control) -> void:
	if submenu.visible:
		hide()
	else:
		show()
