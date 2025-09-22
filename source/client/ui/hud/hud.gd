class_name HUD
extends CanvasLayer


var last_opened_interface: Control
var menus: Dictionary[StringName, Control]

@onready var menu_overlay: Control = $MenuOverlay
@onready var close_button: Button = $MenuOverlay/VBoxContainer/CloseButton
@onready var sub_menu: CanvasLayer = $SubMenu


func _ready() -> void:
	for button: Button in $MenuOverlay/VBoxContainer.get_children():
		if button.text.containsn("CLOSE"):
			button.pressed.connect(_on_overlay_menu_close_button_pressed)
			continue
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
		var path: String = "res://source/client/ui/" + menu_name + "/" + menu_name + "_menu.tscn"
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


# temporary
var attributes: Dictionary
var available_points: int:
	set(value):
		$LevelupButton/Control/VBoxContainer/Label.text = "Available points: %d" % value
		available_points = value

func _on_levelup_button_pressed() -> void:
	print_debug(attributes)
	if not attributes:
		InstanceClient.current.request_data(
			&"attribute.get",
			_on_attribute_received,
		)
	else:
		$LevelupButton/Control.visible = not $LevelupButton/Control.visible


func _on_attribute_received(data: Dictionary) -> void:
	attributes = data
	available_points = data.get("points", 0)
	$LevelupButton/Control/Label.text = "Debug:\n" + str(data)
	$LevelupButton/Control.show()


func _on_vit_button_pressed() -> void:
	if available_points:
		available_points -= 1
		InstanceClient.current.request_data(
			&"attribute.spend",
			print_debug,
			{"attr": "vitality"}
		)
