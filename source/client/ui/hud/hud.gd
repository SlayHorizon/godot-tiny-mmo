class_name HUD
extends Control


@export var sub_menu: Control

var last_opened_interface: Control
var menus: Dictionary[StringName, Control]

@onready var menu_overlay: Control = $MenuOverlay
@onready var close_button: Button = $MenuOverlay/VBoxContainer/CloseButton
@onready var experience_bar: ProgressBar = $Resources/ExperienceBar


func _ready() -> void:
	for button: Button in $MenuOverlay/VBoxContainer.get_children():
		if button.text.containsn("CLOSE"):
			button.pressed.connect(_on_overlay_menu_close_button_pressed)
			continue
		button.pressed.connect(display_menu.bind(button.text.to_lower()))
	
	# Subscribe to XP updates
	ClientState.xp.data_updated.connect(_update_experience_bar)
	_update_experience_bar()


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
	pass # Replace with function body.


func _update_experience_bar() -> void:
	var experience: int = ClientState.xp.data.get("experience", 0)
	var xp_required: int = ClientState.xp.data.get("xp_required", 1)
	
	experience_bar.value = experience
	experience_bar.max_value = xp_required
