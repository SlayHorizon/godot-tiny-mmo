class_name HUD
extends Control

const CHAT_ICON: Texture2D = preload("res://assets/sprites/ui/menu_icons_shadow/32px/message.png")
const CHAT_ICON_UNREAD: Texture2D = preload("res://assets/sprites/ui/menu_icons_shadow/32px/message_exclamation.png")

@export var sub_menu: Control

var notifications: Array[Dictionary]
var menus: Dictionary[StringName, Control]
var _xp_tween: Tween
var _chat_icon: TextureRect
## Bumped on every player.died push so an in-flight respawn countdown can detect that a newer
## death event superseded it and bail (the newest invocation owns the death overlay).
var _death_gen: int = 0
## Gameplay nodes we hid because a menu opened — restored (only these) on close, so nodes with
## their own visibility gating (touch-only sticks, tracked-only quest tracker) that were already
## hidden don't get force-shown.
var _hidden_for_menu: Array[CanvasItem] = []

@onready var menu_overlay: Control = $MenuOverlay
@onready var notification_button: Button = $MenuButtons/ButtonRail/NotificationButton
@onready var menu_button: Button = $MenuButtons/ButtonRail/MenuButton
@onready var chat_button: Button = $MenuButtons/ButtonRail/ChatButton
@onready var actions_button: Button = $MenuButtons/ButtonRail/ActionsButton
@onready var recall_button: Button = $MenuButtons/ButtonRail/RecallButton

## The ACTIONS FLYOUT: the rail's expandable drawer of deliberate, non-twitch character
## actions (docs/ui.md two-tier rule — this is how the HUD scales without top-level creep).
## Today: Recall. Future tenants (torch/light, emotes, sit, …) just join this list.
@onready var _action_items: Array[Button] = [recall_button]
var _actions_open: bool = false
@onready var chat: ChatMenu = $Chat
@onready var twin_sticks: Control = $TwinSticks
@onready var quest_tracker: QuestTracker = $QuestTracker
@onready var trade_panel: Control = $TradePanel
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
	# Chat button now lives in this rail (was self-placed by chat_menu); it toggles the chat
	# feed and badges with the exclamation glyph when a DM is unread.
	_chat_icon = PixelIcon.from_button(chat_button)
	chat_button.pressed.connect(chat.toggle_feed)
	chat.unread_changed.connect(_on_chat_unread)
	# The Actions flyout: one stable rail button expands the drawer of deliberate
	# character actions — reachable on MOBILE (no B key there) without top-level creep.
	PixelIcon.from_button(actions_button)
	PixelIcon.from_button(recall_button)
	actions_button.pressed.connect(_toggle_actions_flyout)
	# Recall: same guarded path as the B key; an accidental tap self-corrects (moving
	# cancels the channel). Firing an action collapses the drawer.
	recall_button.pressed.connect(func() -> void:
		if ClientState.local_player != null:
			ClientState.local_player.request_recall()
		_toggle_actions_flyout())
	Client.subscribe(&"notification", _on_notification_received)
	ClientState.player_profile_requested.connect(open_player_profile)
	ClientState.player_profile_by_peer_requested.connect(open_player_profile_by_peer)
	ClientState.open_menu_requested.connect(_on_menu_requested)
	# Submenus sit ABOVE the chat (z=1) so the chat peek / full feed never floats over an open menu.
	if sub_menu != null:
		sub_menu.z_index = 2
	# The launcher isn't a display_menu submenu, so hook its show/hide into the same HUD-hide path.
	menu_overlay.visibility_changed.connect(_refresh_hud_for_menus)
	# The trade panel is a standalone overlay (not a display_menu) — treat it like a menu too: hide
	# the gameplay HUD + freeze movement while it's open, so HUD clicks can't bleed through behind it.
	trade_panel.visibility_changed.connect(_refresh_hud_for_menus)

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


## Swap the rail chat button to the exclamation glyph while a DM is unread (chat_menu emits).
func _on_chat_unread(has_unread: bool) -> void:
	PixelIcon.set_art(_chat_icon, CHAT_ICON_UNREAD if has_unread else CHAT_ICON)


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
	# Re-entrancy guard: claim a fresh generation. If a newer death push arrives while this
	# countdown is mid-flight, our captured gen goes stale and we bail without touching the
	# overlay, so the newest invocation owns the screen (no early hide / no double text write).
	_death_gen += 1
	var gen: int = _death_gen
	var seconds: int = int(ceil(float(data.get("respawn_in", 2.5))))
	var killed_by: String = str(data.get("killed_by", ""))
	var headline: String = "Slain by %s" % killed_by if not killed_by.is_empty() else "You died"
	death_screen.visible = true
	for remaining: int in range(seconds, 0, -1):
		death_label.text = "%s\nRespawning in %d..." % [headline, remaining]
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self):
			return
		if gen != _death_gen:
			return
	death_screen.visible = false


## Updates the xp bar + level label from progression.get or a combat.reward push.
func _apply_progression(data: Dictionary) -> void:
	if data.has("level"):
		experience_level_label.text = "Lv %d" % int(data["level"])
		# Mirror into ClientState so world nodes (gated portals) can read it without
		# poking at HUD labels.
		ClientState.player_level = int(data["level"])
	if data.has("xp_to_next"):
		experience_bar.max_value = maxi(1, int(data["xp_to_next"]))
	if data.has("experience"):
		var new_xp: int = int(data["experience"])
		if _xp_tween != null and _xp_tween.is_valid():
			_xp_tween.kill()
		if new_xp >= experience_bar.value:
			# XP gained — fill up smoothly. A level-up wraps the value DOWN; snap that
			# (a draining bar reads backwards) so only forward gains animate.
			_xp_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_xp_tween.tween_property(experience_bar, ^"value", new_xp, 0.3)
		else:
			experience_bar.value = new_xp


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
	_refresh_hud_for_menus()


## Gameplay HUD hides behind any open menu OR the launcher (both are semi-transparent, so the
## bars / sticks / chat bleeding through reads messy). We hide the individual gameplay nodes
## rather than the whole HUD, because the launcher is our OWN child (hiding self would hide it
## too); display_menu submenus live in the separate sub_menu container, so they're unaffected.
## Stacked menus are handled by _any_submenu_visible (the HUD stays hidden until ALL close).
func _refresh_hud_for_menus() -> void:
	var covered: bool = _any_submenu_visible() or (menu_overlay != null and menu_overlay.visible) or trade_panel.visible
	if covered:
		# Capture-and-hide ONCE: only nodes currently visible, so we never force-show a node that
		# was hidden by its OWN logic (TwinSticks is touch-only; QuestTracker shows only while a
		# quest is tracked). Re-entrancy from stacked menus is a no-op (list already populated).
		if _hidden_for_menu.is_empty():
			for node: CanvasItem in [
				$TwinSticks, $Chat, $QuestTracker, $ItemSlots, $StatusBar, $AbilityBar, $Resources, $MenuButtons
			]:
				if node.visible:
					node.hide()
					_hidden_for_menu.append(node)
	else:
		for node: CanvasItem in _hidden_for_menu:
			node.show()
		_hidden_for_menu.clear()
		# The quest tracker self-gates on tracked/active state, which may have changed while it was
		# menu-hidden (the player untracked it in the log) — re-derive instead of trusting the blind
		# show() above. Sync-set covers the common cases instantly; refresh() confirms vs live quests.
		quest_tracker.visible = ClientState.tracked_quest_id > 0 # > 0 = real pinned quest (0 = none, -1 = untracked)
		quest_tracker.refresh()


## Suppress player movement whenever a blocking menu is up. Polled each frame (NOT
## event-driven) so a menu-to-menu handoff (the NPC greeting closing as its Shop
## opens) can't leave a one-frame gap where movement slips through. Mobile is already
## covered (the HUD and its sticks hide above). This is the desktop-keyboard gate.
func _process(_delta: float) -> void:
	ClientState.menu_open = _any_submenu_visible() or trade_panel.visible


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


## Open/close the Actions drawer: the rail simply grows by the action buttons while
## open. The Actions button warms up as the "this is expanded" tell; firing any action
## (or re-tapping) collapses it.
func _toggle_actions_flyout() -> void:
	_actions_open = not _actions_open
	for item: Button in _action_items:
		item.visible = _actions_open
	actions_button.modulate = Color(1.0, 0.9, 0.6) if _actions_open else Color.WHITE


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
