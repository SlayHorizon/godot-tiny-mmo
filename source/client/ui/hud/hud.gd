class_name HUD
extends Control


@export var sub_menu: Control

var notifications: Array[Dictionary]
var menus: Dictionary[StringName, Control]

@onready var menu_overlay: Control = $MenuOverlay
@onready var notification_button: Button = $MenuButtons/HBoxContainer/NotificationButton
@onready var menu_button: Button = $MenuButtons/HBoxContainer/MenuButton
@onready var twin_sticks: Control = $TwinSticks
@onready var experience_bar: ProgressBar = $Resources/ExperienceBar
@onready var experience_level_label: Label = $Resources/ExperienceBar/LevelLabel
@onready var death_screen: ColorRect = $DeathScreen
@onready var death_label: Label = $DeathScreen/Label

## UI-sound: button text that gets the softer "back" cue instead of the click.
const BACK_BUTTON_LABELS: Array[String] = ["Close", "Back", "Cancel"]
## Menu open fade-in duration. Kept short + subtle on purpose (a soft arrival, not a flourish).
const MENU_FADE_S: float = 0.10


func _ready() -> void:
	notification_button.visible = false
	notification_button.disabled = true
	# Adopt the buttons' editor-assigned .tscn icons as crisp mounted glyphs (integer-scaled to fit,
	# whole-pixel centered) — visible in the scene, sharp at runtime.
	PixelIcon.from_button(menu_button)
	PixelIcon.from_button(notification_button)
	Client.subscribe(&"notification", _on_notification_received)
	ClientState.player_profile_requested.connect(open_player_profile)
	ClientState.player_profile_by_peer_requested.connect(open_player_profile_by_peer)
	ClientState.open_menu_requested.connect(_on_menu_requested)

	ClientState.input_changed.connect(_on_input_type_changed)

	# Character level / xp bar.
	Client.subscribe(&"combat.reward", _apply_progression)
	Client.subscribe(&"player.died", _on_player_died)
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer):
		_refresh_progression()
		_maybe_show_welcome())
	_refresh_progression()

	# Sparring countdown — big centered text fired each second by the server.
	Client.subscribe(&"sparring.countdown", _on_sparring_countdown)

	# Dungeon run HUD (live clock + revive pool) — self-contained; shows itself on dungeon.hud pushes.
	add_child(DungeonHud.new())

	# UI sound: wire every Button under the HUD to tap/hover cues (menus build theirs lazily, so also
	# watch node_added). The gateway has its own wiring; this is scoped to the in-game HUD subtree.
	_wire_subtree(self)
	get_tree().node_added.connect(_on_node_added)


## Fetch the current level/xp once (e.g. on spawn / map change).
func _refresh_progression() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"progression.get", _apply_progression, {}, InstanceClient.current.name)


## First-run welcome modal, shown once via a client settings flag (so per install, not per character).
## Good enough for the alpha intro; the same guidance lives in the Help menu. Make it first-time-only with
## a server flag later if existing players should skip it.
func _maybe_show_welcome() -> void:
	if ClientState.settings.get_value(&"onboarding", &"seen_welcome"):
		# Welcome already seen; a web player may still have the one-time web notice pending.
		_maybe_show_web_notice()
		return
	ClientState.settings.set_value(&"onboarding", &"seen_welcome", true)
	var welcome: WelcomeScreen = WelcomeScreen.new()
	# Chain the web-only download notice so the two first-run modals never stack on screen.
	welcome.tree_exited.connect(_maybe_show_web_notice, CONNECT_DEFERRED)
	add_child(welcome)


## One-time "you're on the web build, grab the download" nudge. Web only, shown once via a
## client flag (per install, like the welcome modal). Edit the copy + URL in web_notice.gd.
func _maybe_show_web_notice() -> void:
	if not OS.has_feature("web"):
		return
	if ClientState.settings.get_value(&"onboarding", &"seen_web_notice"):
		return
	ClientState.settings.set_value(&"onboarding", &"seen_web_notice", true)
	add_child(WebNotice.new())


## Shows the death overlay with a per-second countdown until the server respawns us.
func _on_player_died(data: Dictionary) -> void:
	var seconds: int = int(ceil(float(data.get("respawn_in", 2.5))))
	var killed_by: String = str(data.get("killed_by", ""))
	var headline: String = "Slain by %s" % killed_by if not killed_by.is_empty() else "You died"
	death_screen.visible = true
	for remaining: int in range(seconds, 0, -1):
		death_label.text = "%s\nRespawning in %d..." % [headline, remaining]
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


## Open a profile by the target's PEER id (a world click) — the server resolves it to
## the persistent player_id. Mirrors open_player_profile for the by-peer path.
func open_player_profile_by_peer(peer_id: int) -> void:
	display_menu(&"player_profile")
	menus[&"player_profile"].open_player_profile_by_peer(peer_id)


func _on_submenu_visiblity_changed(_menu: Control) -> void:
	# Show the HUD only when NO submenu remains open. Closing a STACKED menu (e.g.
	# the full-screen mastery tree over the character window) must not pop the HUD
	# back up while another menu is still visible behind it.
	if _any_submenu_visible():
		hide()
	else:
		show()


## Suppress player movement whenever a blocking menu is up. Polled each frame (NOT
## event-driven) so a menu-to-menu handoff (the NPC greeting closing as its Shop
## opens) can't leave a one-frame gap where movement slips through. Mobile is already
## covered (the HUD and its sticks hide above). This is the desktop-keyboard gate.
func _process(_delta: float) -> void:
	ClientState.menu_open = _any_submenu_visible()


## True if any display_menu submenu is currently visible.
func _any_submenu_visible() -> bool:
	for menu: Control in menus.values():
		if menu.visible:
			return true
	return false


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
	_animate_menu_open(menus[menu_name])
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


# --- UI sound + menu motion ------------------------------------------------

func _play_click() -> void:
	UISound.click()


func _play_back() -> void:
	UISound.back()


func _play_hover() -> void:
	UISound.hover()


## Give a button press + hover cues (idempotent). Close/Back/Cancel buttons get the softer back cue.
func _wire_button(button: Button) -> void:
	if not (button.pressed.is_connected(_play_click) or button.pressed.is_connected(_play_back)):
		var press: Callable = _play_back if button.text in BACK_BUTTON_LABELS else _play_click
		button.pressed.connect(press)
	if not button.mouse_entered.is_connected(_play_hover):
		button.mouse_entered.connect(_play_hover)


## Wire every Button currently under [root].
func _wire_subtree(root: Node) -> void:
	for b: Node in root.find_children("*", "Button", true, false):
		_wire_button(b as Button)


## Any Button added under the HUD later (lazily-built menus) gets wired automatically.
func _on_node_added(node: Node) -> void:
	if node is Button and is_ancestor_of(node):
		_wire_button(node as Button)


## Fade a just-shown menu in + play the reveal cue, so menus arrive with a little motion + sound
## instead of snapping on. Open only — close stays an instant hide for now.
func _animate_menu_open(menu: Control) -> void:
	UISound.reveal()
	menu.modulate.a = 0.0
	create_tween().tween_property(menu, ^"modulate:a", 1.0, MENU_FADE_S)
