class_name HUD
extends Control


@export var sub_menu: Control

var notifications: Array[Dictionary]
var menus: Dictionary[StringName, Control]

@onready var menu_overlay: Control = $MenuOverlay
@onready var close_button: Button = $MenuOverlay/VBoxContainer/CloseButton
@onready var notification_button: Button = $MenuButtons/HBoxContainer/NotificationButton


func _ready() -> void:
	notification_button.visible = false
	notification_button.disabled = true
	Client.subscribe(&"notification", _on_notification_received)
	ClientState.player_profile_requested.connect(open_player_profile)

	for button: Button in $MenuOverlay/VBoxContainer.get_children():
		if button.text.containsn("CLOSE"):
			button.pressed.connect(_on_overlay_menu_close_button_pressed)
		else:
			button.pressed.connect(display_menu.bind(button.text.to_lower()))


func _on_overlay_menu_close_button_pressed() -> void:
	menu_overlay.hide()


func open_player_profile(player_id: int) -> void:
	display_menu(&"player_profile")
	menus[&"player_profile"].open_player_profile(player_id)


func _on_submenu_visiblity_changed(menu: Control) -> void:
	if menu.visible:
		hide()
	else:
		show()


func display_menu(menu_name: StringName) -> void:
	if not menus.has(menu_name):
		var path: String = "res://source/client/ui/menus/" + menu_name + "/" + menu_name + "_menu.tscn"
		if not ResourceLoader.exists(path):
			return
		var new_menu: Control = load(path).instantiate()
		new_menu.visibility_changed.connect(_on_submenu_visiblity_changed.bind(new_menu))
		sub_menu.add_child(new_menu)
		menus[menu_name] = new_menu
	menus[menu_name].show()


func _on_overlay_menu_button_pressed() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(menu_overlay, ^"position:x", menu_overlay.position.x + menu_overlay.size.x, 0.0)
	tween.tween_callback(menu_overlay.show)
	tween.tween_property(menu_overlay, ^"position:x", 815.0, 0.3)


func _on_notification_button_pressed() -> void:
	# Weird safety case where notification button could be visible
	if notifications.is_empty():
		notification_button.visible = false
		notification_button.disabled = true
		return
	var notification_payload: Dictionary = notifications.pop_back()
	$NotificationPopup.pop_notification(notification_payload.get("topic", ""), notification)
	if notifications.is_empty():
		notification_button.visible = false
		notification_button.disabled = true


func _on_profile_button_pressed() -> void:
	open_player_profile(0)


func _on_notification_received(payload: Dictionary) -> void:
	print_debug("NOTIF ", payload)
	notifications.append(payload)
	notification_button.visible = true
	notification_button.disabled = false
