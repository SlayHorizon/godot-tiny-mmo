class_name HUD
extends Control


@export var sub_menu: Control

var notifications: Array[Dictionary]
var menus: Dictionary[StringName, Control]

@onready var menu_overlay: Control = $MenuOverlay
@onready var notification_button: Button = $MenuButtons/HBoxContainer/NotificationButton
@onready var twin_sticks: Control = $TwinSticks
@onready var experience_bar: ProgressBar = $Resources/ExperienceBar
@onready var experience_level_label: Label = $Resources/ExperienceBar/LevelLabel
@onready var death_screen: ColorRect = $DeathScreen
@onready var death_label: Label = $DeathScreen/Label


func _ready() -> void:
	notification_button.visible = false
	notification_button.disabled = true
	Client.subscribe(&"notification", _on_notification_received)
	ClientState.player_profile_requested.connect(open_player_profile)
	ClientState.open_menu_requested.connect(_on_menu_requested)

	ClientState.input_changed.connect(_on_input_type_changed)

	# Character level / xp bar.
	Client.subscribe(&"combat.reward", _apply_progression)
	Client.subscribe(&"player.died", _on_player_died)
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _refresh_progression())
	_refresh_progression()

	# Sparring countdown — big centered text fired each second by the server.
	Client.subscribe(&"sparring.countdown", _on_sparring_countdown)


## Fetch the current level/xp once (e.g. on spawn / map change).
func _refresh_progression() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"progression.get", _apply_progression, {}, InstanceClient.current.name)


## Shows the death overlay with a per-second countdown until the server respawns us.
func _on_player_died(data: Dictionary) -> void:
	var seconds: int = int(ceil(float(data.get("respawn_in", 2.5))))
	death_screen.visible = true
	for remaining: int in range(seconds, 0, -1):
		death_label.text = "You died\nRespawning in %d..." % remaining
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self):
			return
	death_screen.visible = false


## Updates the xp bar + level label from progression.get or a combat.reward push.
func _apply_progression(data: Dictionary) -> void:
	if data.has("level"):
		experience_level_label.text = "Lv %d" % int(data["level"])
	if data.has("xp_to_next"):
		experience_bar.max_value = maxi(1, int(data["xp_to_next"]))
	if data.has("experience"):
		experience_bar.value = int(data["experience"])


func _on_input_type_changed(input_type: InputComponent.InputType) -> void:
	twin_sticks.enabled = input_type == InputComponent.InputType.TOUCH


func _on_menu_requested(menu_name: StringName, arg: Variant) -> void:
	display_menu(menu_name, arg)


func open_player_profile(player_id: int) -> void:
	display_menu(&"player_profile")
	menus[&"player_profile"].open_player_profile(player_id)


func _on_submenu_visiblity_changed(menu: Control) -> void:
	if menu.visible:
		hide()
	else:
		show()


func display_menu(menu_name: StringName, arg: Variant = null) -> void:
	if not menus.has(menu_name):
		var path: String = "res://source/client/ui/menus/" + menu_name + "/" + menu_name + "_menu.tscn"
		if not ResourceLoader.exists(path):
			return
		var new_menu: Control = load(path).instantiate()
		new_menu.visibility_changed.connect(_on_submenu_visiblity_changed.bind(new_menu))
		sub_menu.add_child(new_menu)
		menus[menu_name] = new_menu
	menus[menu_name].show()
	if arg != null and menus[menu_name].has_method(&"open"):
		menus[menu_name].open(arg)


func _on_overlay_menu_button_pressed() -> void:
	menu_overlay.open()


func _on_notification_button_pressed() -> void:
	# Weird safety case where notification button could be visible
	if notifications.is_empty():
		notification_button.visible = false
		notification_button.disabled = true
		return
	var notification_payload: Dictionary = notifications.pop_back()
	$NotificationPopup.pop_notification(notification_payload.get("topic", ""), notification_payload)
	if notifications.is_empty():
		notification_button.visible = false
		notification_button.disabled = true


func _on_notification_received(payload: Dictionary) -> void:
	notifications.append(payload)
	notification_button.visible = true
	notification_button.disabled = false


## Big centered "3 / 2 / 1 / FIGHT!" pushed each second of the sparring countdown.
## Lazily creates the label so we don't carry the node when nobody spars.
##
## Smoothing: each tick is a hard text swap (no fade between digits — fading
## while the next digit arrives just looks twitchy). Only the final FIGHT!
## tick (seconds=0) fades out, and we kill any prior tween so it can't leak
## across into the next match.
var _countdown_tween: Tween

func _on_sparring_countdown(payload: Dictionary) -> void:
	var label: Label = get_node_or_null(^"SparringCountdown") as Label
	if label == null:
		label = Label.new()
		label.name = "SparringCountdown"
		label.anchor_left = 0.5
		label.anchor_top = 0.5
		label.anchor_right = 0.5
		label.anchor_bottom = 0.5
		label.offset_left = -120
		label.offset_top = -40
		label.offset_right = 120
		label.offset_bottom = 40
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 64)
		add_child(label)

	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
		_countdown_tween = null

	label.text = str(payload.get("text", ""))
	label.modulate.a = 1.0
	label.visible = true

	# Only the FIGHT! tick auto-fades. Intermediate digits stay solid until
	# the next push replaces them, which keeps the cadence crisp.
	if int(payload.get("seconds", 1)) > 0:
		return

	_countdown_tween = create_tween()
	_countdown_tween.tween_interval(0.6)
	_countdown_tween.tween_property(label, ^"modulate:a", 0.0, 0.4)
	_countdown_tween.tween_callback(func():
		label.visible = false
		label.modulate.a = 1.0
		_countdown_tween = null
	)
