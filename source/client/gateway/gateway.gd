extends Control


const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")

var account_id: int
var account_name: String
var session_id: String
var local_id: String

var current_world_id: int
var current_character_id: int
var selected_skin_id: int = 1

var menu_stack: Array[Control]

# Guards the empty-world-list auto-retry so only one poll loop runs at a time.
var _world_poll_active: bool = false

# "Focus navigation" mode: the player is driving the menu by keyboard or gamepad
# (not mouse/touch). We only force focus + show the focus highlight in this mode,
# so pointer users never get a stray focus ring or a popped virtual keyboard.
var _focus_nav: bool = false
# Device-aware focus ring (the theme's Button focus style is intentionally empty,
# which hides focus from mouse users — we draw our own only in _focus_nav mode).
var _focus_highlight: Panel

# --- Gateway palettes (theme resources) ------------------------------------
# Each gateway_*.tres in THEME_DIR is a GatewayTheme carrying its palette + the
# baked styleboxes + its backdrop. We scan the folder, pick one (saved pref /
# default / random), and assign it to `theme` — inheritance styles the whole
# subtree. Swapping palette = reassigning `theme`. The per-node looks (panel /
# button / divider variations) are set in gateway.tscn, not here.
const THEME_DIR: String = "res://source/client/ui/themes/gateway/"
const DEFAULT_PALETTE: StringName = &"horizon"
# Palette preference lives in the shared client settings (ClientState.settings)
# under section [gateway] — not a private file. Seeded in client_default_settings.cfg.
const _SETTINGS_SECTION: StringName = &"gateway"
const _SETTING_PALETTE: StringName = &"palette"
const _SETTING_RANDOMIZE: StringName = &"randomize"
var _themes: Dictionary[StringName, GatewayTheme] = {}
var _theme_order: Array[StringName] = []
var current_theme: StringName = DEFAULT_PALETTE

# Community / support links opened by the global "More" menu. Empty = not provided
# yet → that button is disabled rather than opening a dead link.
const LINK_WEBSITE: String = "https://ekoniaonline.com"
const LINK_DISCORD: String = "https://discord.gg/QE5JwpFzgK"

# The persistent top-right "More" menu. Its nodes live in the scene (root-level,
# unique-named); only the dynamic wiring is in code. See _wire_more_menu.
@onready var _more_menu: PanelContainer = %MoreMenu
@onready var _more_backdrop: ColorRect = %MoreBackdrop
@onready var _more_logout: Button = %LogoutButton


# Character-creation skin picker — Prev/Next cycle through these (the big centre
# preview shows the current one). Curated player-appropriate sprites; add slugs to
# offer more starter looks.
const PLAYER_SKINS: PackedStringArray = [
	"knight", "rogue", "wizard", "bandit_fighter", "bandit_scout",
	"bandit_sorcerer", "bandit_tracker", "goblin",
]
var _skin_index: int = 0
var _skin_preview: AnimatedSprite2D
var _skin_name_label: Label

@onready var main_panel: PanelContainer = $MainPanel
@onready var login_panel: PanelContainer = $LoginPanel
@onready var popup_panel: PanelContainer = $PopupPanel

@onready var back_button: Button = $BackButton

@onready var http_request: HTTPRequest = $HTTPRequest


func _ready() -> void:
	menu_stack.append(main_panel)
	back_button.hide()

	prepare_character_creation_menu()

	# Wire the world-list refresh button (disabled in the scene until there's a
	# live endpoint to hit — now there is: GatewayAPI.worlds()).
	var update_button: Button = $WorldSelection/VBoxContainer/Button
	update_button.disabled = false
	update_button.pressed.connect(_on_world_update_button_pressed)

	_setup_focus_highlight()
	_setup_password_fields()
	_wire_more_menu()
	_load_gateway_themes()
	_apply_gateway_theme(_pick_startup_palette())
	# Live-apply a palette picked in the Settings menu (the gateway's own $Settings
	# overlay shows the same dropdown) — no relaunch needed.
	ClientState.settings.setting_changed.connect(_on_settings_changed)

	local_id = CmdlineUtils.get_parsed_args().get("id", "")

	if not await try_auto_login():
		popup_panel.hide()
		$MainPanel.show()
		$MainPanel/VBoxContainer/VBoxContainer/LoginButton.grab_focus()


func handle_success_login(d: Dictionary) -> void:
	var worlds: Dictionary = d.get("w", {})

	session_id = d.get("session_id", 0)

	account_name = d.get("name", "")
	account_id = d.get("id", 0)
	current_character_id = d.get("character_id", 0)

	var last_world_name: String = d.get("world_name", "")
	var is_last_world_online: bool = false

	for world_id: String in worlds:
		if worlds[world_id].get("info", {}).get("name", "-1") == last_world_name:
			current_world_id = world_id.to_int()
			is_last_world_online = true

	populate_worlds(worlds)

	if is_last_world_online:
		$AlreadyConnectedPanel/ContinueButton.text = tr("CONTINUE_WORLD_ACC") % [last_world_name, account_name]
		popup_panel.hide()
		_show($AlreadyConnectedPanel, false)
	else:
		popup_panel.hide()
		$MainPanel.show()
		fill_connection_info(account_name, account_id)
		_show($WorldSelection, false)


func do_request(
	method: HTTPClient.Method,
	path: String,
	payload: Dictionary,
) -> Dictionary:
	if http_request.get_http_client_status() == HTTPClient.Status.STATUS_CONNECTED:
		return {"error": "request_error"}

	var custom_headers: PackedStringArray
	custom_headers.append("Content-Type: application/json")
	
	var error: Error = http_request.request(
		path,
		custom_headers,
		method,
		JSON.stringify(payload)
	)

	if error != OK:
		push_error("An error occurred in the HTTP request.")
		return {ok=false, error="request_error", code=error}

	var args: Array = await http_request.request_completed
	var result: int = args[0]
	if result != OK:
		return {"error": "connection_failed", "code": result}

	var response_code: int = args[1]
	var headers: PackedStringArray = args[2]
	var body: PackedByteArray = args[3]

	var data: Variant = JSON.parse_string(body.get_string_from_ascii())
	if data is Dictionary:
		return data
	return {"error": "bad_response"}


func _show(next: Control, can_back: bool = true) -> void:
	if menu_stack.size():
		menu_stack.back().hide()
	if not can_back:
		menu_stack.clear()
	next.show()
	menu_stack.append(next)
	back_button.visible = can_back
	# Land the keyboard/gamepad cursor on the new panel's first control so a
	# non-mouse player always has somewhere to navigate from.
	if _focus_nav:
		_focus_first_in(next)


# _input (not _unhandled_input): when a control has focus the GUI consumes
# navigation events, so they'd never reach _unhandled_input. We only observe the
# device here — we don't swallow navigation.
func _input(event: InputEvent) -> void:
	# Keyboard or gamepad → focus-nav mode; mouse/touch → pointer mode. Guarded on
	# transitions so this stays cheap despite per-frame mouse-motion / stick events.
	if (event is InputEventKey and (event as InputEventKey).pressed) \
			or event is InputEventJoypadButton \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		if not _focus_nav:
			_focus_nav = true
			set_process(true)  # only track the ring while actually focus-navigating
			_refresh_focus_highlight()
	elif event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch:
		if _focus_nav:
			_focus_nav = false
			_focus_highlight.hide()
			set_process(false)

	# B / Escape steps back, mirroring the on-screen Back button — but not while a
	# popup is up (it owns the screen).
	if event.is_action_pressed(&"ui_cancel") and back_button.visible and not popup_panel.visible:
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()

	# Debug: cycle the gateway palette (gold → horizon → forest → fireforge).
	if event is InputEventKey and (event as InputEventKey).pressed \
			and ((event as InputEventKey).keycode == KEY_F3 \
			or (event as InputEventKey).physical_keycode == KEY_F3):
		_cycle_theme()


## Grab focus on the first visible, focusable Control under `node` (depth-first).
## Returns true once it lands focus somewhere.
func _focus_first_in(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is Control:
			var control: Control = child
			if not control.visible:
				continue
			if control.focus_mode != Control.FOCUS_NONE:
				control.grab_focus()
				return true
		if _focus_first_in(child):
			return true
	return false


func _on_login_button_pressed() -> void:
	_show(login_panel)


func _on_login_login_button_pressed() -> void:
	var account_name_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer/LineEdit
	var password_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit

	var username: String = account_name_edit.text
	var password: String = password_edit.text

	var login_button: Button = $LoginPanel/VBoxContainer/VBoxContainer/LoginButton
	login_button.disabled = true
	if (
		CredentialsUtils.validate_username(username).code != CredentialsUtils.UsernameError.OK
		or CredentialsUtils.validate_password(password).code != CredentialsUtils.UsernameError.OK
	):
		#await popup_panel.confirm_message(str(response))
		login_button.disabled = false
		return

	popup_panel.display_waiting_popup()
	var response: Dictionary = await request_login(username, password)
	if response.has("error"):
		await popup_panel.confirm_message(GatewayError.humanize(response))
		login_button.disabled = false
		return

	session_id = response.get("session_id")

	save_refresh_token("%s\n%s" % [username, password], "user://%ssession.dat" % local_id)

	
	populate_worlds(response.get("w", {}))
	fill_connection_info(response["name"], response["id"])

	popup_panel.hide()
	_show($WorldSelection, false)


func _on_guest_button_pressed() -> void:
	popup_panel.display_waiting_popup()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.guest(),
		{}
	)
	if d.has("error"):
		await popup_panel.confirm_message(GatewayError.humanize(d))
		return

	session_id = d.get("session_id", 0)

	fill_connection_info(d.get("name", ""), d.get("id", 0))
	populate_worlds(d.get("w", {}))

	popup_panel.hide()
	_show($WorldSelection, false)


func _on_world_selected(world_id: int) -> void:
	$WorldSelection.hide()
	popup_panel.display_waiting_popup()
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_characters(),
		{
			GatewayAPI.KEY_WORLD_ID: world_id,
			GatewayAPI.KEY_ACCOUNT_ID: account_id,
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_TOKEN_ID: session_id
		}
	)
	if d.has("error"):
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$WorldSelection.show()
		return

	var container: HBoxContainer = $CharacterSelection/VBoxContainer/HBoxContainer
	var character_ids: Array = d.keys()
	var slots: Array[Node] = container.get_children()
	for slot_index: int in slots.size():
		var button: Button = slots[slot_index]
		# Wrap so the long "Create New Character" card stays the same width as the
		# others instead of stretching wider.
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Clear prior card content (portrait + label from a previously-shown world).
		for content: Node in button.get_children():
			content.queue_free()
		# Connections are bound callables, so is_connected(unbound) never matched —
		# clear every prior connection so re-entering doesn't stack duplicates.
		for conn: Dictionary in button.pressed.get_connections():
			button.pressed.disconnect(conn["callable"])
		# Slot index tracks the button position directly (the old manual counter
		# skipped its increment on `continue`, desyncing every later slot).
		if slot_index < character_ids.size():
			var cid: String = str(character_ids[slot_index])
			var entry: Dictionary = d.get(cid, {})
			if entry.has_all(["name", "level"]):  # "class" dropped — no classes anymore
				_fill_character_card(button, entry)
				button.pressed.connect(_on_character_selected.bind(world_id, cid.to_int()))
				continue
		button.text = tr("CREATE_NEW_CHAR")
		button.pressed.connect(_on_character_selected.bind(world_id, -1))
	popup_panel.hide()
	_show($CharacterSelection)


func _on_character_selected(world_id: int, character_id: int) -> void:
	current_world_id = world_id
	if character_id == -1:
		_show($CharacterCreation)
		return

	$CharacterSelection.hide()
	$BackButton.hide()
	popup_panel.display_waiting_popup()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_enter(),
		{
			GatewayAPI.KEY_TOKEN_ID: session_id,
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_WORLD_ID: world_id,
			GatewayAPI.KEY_CHAR_ID: character_id
		}
	)
	if d.has("error"):
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$CharacterSelection.show()
		$BackButton.show()
		return

	Client.connect_to_server(d["address"], d["port"], d["auth-token"])
	queue_free.call_deferred()


## Dress an existing-character card: the character's actual sprite (idle pose) up
## top, name + level pinned to the bottom. Children use MOUSE_FILTER_IGNORE so the
## card button still receives the click.
func _fill_character_card(button: Button, entry: Dictionary) -> void:
	button.text = ""
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", int(entry.get("skin", 1))) as SpriteFrames
	if frames:
		var portrait: AnimatedSprite2D = AnimatedSprite2D.new()
		portrait.sprite_frames = frames
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel sprite
		portrait.scale = Vector2(2.4, 2.4)
		portrait.position = Vector2(75.0, 100.0)  # upper-centre of the 150x250 card
		var anim: StringName = _card_anim(frames)
		if not anim.is_empty():
			portrait.play(anim)
		button.add_child(portrait)
	var info: Label = Label.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_top = -54.0
	info.offset_bottom = -12.0
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.text = tr("NAME_LEVEL") % [entry["name"], entry["level"]]
	button.add_child(info)


## Prefer an idle pose for the card, fall back to run, then the first animation.
func _card_anim(frames: SpriteFrames) -> StringName:
	for candidate: StringName in [&"idle", &"run"]:
		if frames.has_animation(candidate):
			return candidate
	var names: PackedStringArray = frames.get_animation_names()
	if not names.is_empty():
		return StringName(names[0])
	return &""


func _on_create_character_button_pressed() -> void:
	var username_edit: LineEdit = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer2/LineEdit

	var create_button: Button = $CharacterCreation/VBoxContainer/VBoxContainer/CreateButton
	create_button.disabled = true
	$BackButton.hide()
	$CharacterCreation.hide()

	var result: Dictionary
	result = CredentialsUtils.validate_username(username_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message(tr("USERNAME") + result.message)
		create_button.disabled = false
		$BackButton.show()
		$CharacterCreation.show()
		return

	popup_panel.display_waiting_popup()
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_create_char(),
		{
			GatewayAPI.KEY_TOKEN_ID: session_id,
			"data": {
				"name": username_edit.text,
				"skin": selected_skin_id,
			},
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_WORLD_ID: current_world_id
		}
	)
	if d.has("error"):
		await popup_panel.confirm_message(GatewayError.humanize(d))
		create_button.disabled = false
		$CharacterCreation.show()
		return

	Client.connect_to_server(
		d["address"],
		d["port"],
		d["auth-token"]
	)
	queue_free.call_deferred()


func create_account() -> void:
	var name_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer/LineEdit
	var password_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	var password_repeat_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer3/LineEdit

	if password_edit.text != password_repeat_edit.text:
		await popup_panel.confirm_message(tr("PASSWORDS_DONT_MATCH"))
		return
	
	var result: Dictionary
	result = CredentialsUtils.validate_username(name_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message(tr("USERNAME") + result.message)
		return
	result = CredentialsUtils.validate_password(password_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message(tr("PASSWORD") + ":\n" + result.message)
		return
	
	$CreateAccountPanel.hide()
	popup_panel.display_waiting_popup()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.account_create(),
		{
			GatewayAPI.KEY_ACCOUNT_USERNAME: name_edit.text,
			GatewayAPI.KEY_ACCOUNT_PASSWORD: password_edit.text,
		}
	)
	if d.has("error"):
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$CreateAccountPanel.show()
		return
	
	save_refresh_token(name_edit.text + "\n" + password_edit.text, "user://%ssession.dat" % local_id)


	fill_connection_info(d["name"], d["id"])
	populate_worlds(d.get("w", {}))
	
	popup_panel.hide()
	_show($WorldSelection, false)


func _on_create_account_button_pressed() -> void:
	_show($CreateAccountPanel)


func populate_worlds(world_info: Dictionary) -> void:
	var container: HBoxContainer = $WorldSelection/VBoxContainer/HBoxContainer
	for child: Node in container.get_children():
		child.queue_free()

	if world_info.is_empty():
		# No world online: show a clear in-place message (not a dead-end countdown
		# popup) and quietly auto-retry while the player stays on this screen. They
		# can also hit Update to refresh manually.
		var empty_label: Label = Label.new()
		empty_label.text = tr("NO_WORLDS_ONLINE")
		empty_label.custom_minimum_size = Vector2(360.0, 250.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		container.add_child(empty_label)
		_poll_worlds_while_empty()
		return

	for world_id: String in world_info:
		add_world_card(world_info.get(world_id, {}).get("info", {}), world_id.to_int())

	# A fresh list just arrived — lock Update briefly so it can't be spammed (the
	# boot-time list counts too, since this runs on every populate).
	_start_update_cooldown()


func _on_world_update_button_pressed() -> void:
	await refresh_worlds()


## Re-fetch the live world list from the gateway without re-logging-in. Cheap —
## the gateway serves it from its cached roster (GatewayAPI.worlds()).
func refresh_worlds() -> void:
	var update_button: Button = $WorldSelection/VBoxContainer/Button
	update_button.disabled = true
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.worlds(),
		{}
	)
	if d.has("error"):
		update_button.disabled = false  # request failed — allow an immediate retry
		return
	populate_worlds(d.get("w", {}))  # success → populate starts the cooldown


## Lock the Update button for 5s after a refresh so it can't be hammered.
func _start_update_cooldown() -> void:
	var update_button: Button = $WorldSelection/VBoxContainer/Button
	update_button.disabled = true
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(update_button):
		update_button.disabled = false


## While the list is empty and the player is still on the selection screen,
## quietly re-poll so a world coming online appears without a manual refresh.
## Guarded by _world_poll_active so only one loop ever runs.
func _poll_worlds_while_empty() -> void:
	if _world_poll_active:
		return
	_world_poll_active = true
	# populate_worlds() runs just before the caller shows WorldSelection, so let
	# that happen before we gate the loop on the panel's visibility.
	await get_tree().process_frame
	while $WorldSelection.visible:
		await get_tree().create_timer(5.0).timeout
		if not $WorldSelection.visible:
			break
		var d: Dictionary = await do_request(
			HTTPClient.Method.METHOD_POST,
			GatewayAPI.worlds(),
			{}
		)
		if d.has("error"):
			continue
		var w: Dictionary = d.get("w", {})
		if not w.is_empty():
			_world_poll_active = false
			populate_worlds(w)
			return
	_world_poll_active = false


func fill_connection_info(_account_name: String, _account_id: int) -> void:
	account_name = _account_name
	account_id = _account_id
	# Player-facing connection status — confirms we reached the backend. Drops the
	# account-ID, which was dev-only debug. (Initial "Not connected yet" is in the
	# scene and stays until the first successful response.)
	$ConnectionInfo.text = tr("CONNECTED_AS") % account_name


func add_world_card(world_info: Dictionary, world_id: int) -> Button:
	var container: HBoxContainer = $WorldSelection/VBoxContainer/HBoxContainer

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(150.0, 250.0)
	button.pressed.connect(_on_world_selected.bind(world_id))
	# Styled by the gateway theme's default Button (inherited) — no per-card call.

	var text_label: RichTextLabel = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_label.mouse_filter = Control.MOUSE_FILTER_PASS

	text_label.append_text(
		"[font_size=20][b]%s[/b][/font_size]\n" % world_info.get("name", "Unknown World")
	)
	text_label.append_text(
		"\n[i][font_size=12]\"%s\"[/font_size][/i]\n" % tr(world_info.get("motd", ""))
	)
	text_label.append_text(
		"\n[font_size=13][b]%s[/b][/font_size]\n" % "PvP" if world_info.get("pvp", true) else "No PvP"
	)

	button.add_child(text_label)

	container.add_child(button)
	return button


func _on_continue_button_pressed() -> void:
	$AlreadyConnectedPanel.hide()
	popup_panel.display_waiting_popup()
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.world_enter(),
		{
			GatewayAPI.KEY_TOKEN_ID: session_id,
			GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
			GatewayAPI.KEY_WORLD_ID: current_world_id,
			GatewayAPI.KEY_CHAR_ID: current_character_id
		}
	)
	if d.has("error"):
		await popup_panel.confirm_message(GatewayError.humanize(d))
		$AlreadyConnectedPanel.show()
		return

	Client.connect_to_server(d["address"], d["port"], d["auth-token"])
	queue_free.call_deferred()


func _on_change_button_pressed() -> void:
	# Keep the stack so Back returns to the resume (AlreadyConnected) screen.
	_show($WorldSelection, true)


## Wire the persistent top-right "More" menu. Its nodes (root-level, unique-named:
## %MoreButton, %MoreMenu, %MoreBackdrop + the named entries) and their look live in
## the scene; only the dynamics are here: signal connections, the context-aware
## Logout, and the version text.
func _wire_more_menu() -> void:
	(%MoreButton as Button).pressed.connect(func() -> void: _set_more_open(not _more_menu.visible))
	_more_backdrop.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				_set_more_open(false)
	)

	# Settings entry opens the full Settings overlay (and closes the menu).
	(%SettingsEntry as Button).pressed.connect(
		func() -> void:
			_set_more_open(false)
			$Settings.visible = true
	)

	# Community links → browser (disabled when no URL is set, see _wire_link).
	_wire_link(%DiscordButton as Button, LINK_DISCORD)
	_wire_link(%WebsiteButton as Button, LINK_WEBSITE)

	# Session: Logout (shown only with an active session, see _set_more_open) + Quit
	# (desktop/console only).
	_more_logout.pressed.connect(_logout)
	if OS.has_feature("mobile"):
		(%QuitButton as Button).hide()  # phones don't button-quit; use the OS app switcher
	else:
		(%QuitButton as Button).pressed.connect(get_tree().quit)

	(%MoreBackButton as Button).pressed.connect(func() -> void: _set_more_open(false))
	(%VersionLabel as Label).text = "v" + GatewayAPI.game_version()


## Open/close the global More menu (flyout + modal backdrop). On open it refreshes
## the context-sensitive entries — Logout only makes sense with an active session.
func _set_more_open(open: bool) -> void:
	if open:
		_more_logout.visible = not session_id.is_empty()
	_more_menu.visible = open
	_more_backdrop.visible = open


## Wire a flyout link button to open `url` in the browser. Empty url → disable the
## button (reads as "not available yet" instead of a dead click).
func _wire_link(button: Button, url: String) -> void:
	if url.is_empty():
		button.disabled = true
		return
	button.pressed.connect(func() -> void: OS.shell_open(url))


## Forget the saved session and return to the main menu so another account can log
## in. The auto-login token lives in session.dat (see save_refresh_token).
func _logout() -> void:
	var file_path: String = "user://%ssession.dat" % local_id
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	session_id = ""  # clears the active session → More's Logout hides again
	_set_more_open(false)
	# Logout can be triggered from any screen (world/character select, character
	# creation, …), so hide them all — not just the resume panel — before returning
	# to the main menu, or the old screen stays visible and clickable on top.
	for panel: Control in [
		login_panel, $CreateAccountPanel, $WorldSelection,
		$CharacterSelection, $CharacterCreation, $AlreadyConnectedPanel, popup_panel,
	]:
		panel.hide()
	menu_stack.clear()
	menu_stack.append(main_panel)
	main_panel.show()
	back_button.hide()
	if _focus_nav:
		_focus_first_in(main_panel)


#func _on_swap_theme_button_toggled(toggled_on: bool) -> void:
	#if not $AudioStreamPlayer.playing:
	#	$AudioStreamPlayer.play()
	#if toggled_on:
	#	$Background.texture = preload("uid://cfihbj71a4y35")
	#	Client.theme = preload("uid://c2nr0o8v7vb75")
	#else:
	#	$Background.texture = preload("uid://cn5blfyqokda6")
	#	Client.theme = preload("uid://cf1ayo3dckj67")
	#theme = Client.theme


func _on_back_button_pressed() -> void:
	if menu_stack.size():
		menu_stack.pop_back().hide()
		if menu_stack.size():
			menu_stack.back().show()
			# Going back must re-home focus on the revealed panel for non-mouse
			# players (back doesn't route through _show, so do it here).
			if _focus_nav:
				_focus_first_in(menu_stack.back())
		if menu_stack.size() < 2:
			back_button.hide()


# --- Focus highlight (device-aware) ---------------------------------------

## Build the overlay ring once and start listening for focus changes.
func _setup_focus_highlight() -> void:
	_focus_highlight = Panel.new()
	_focus_highlight.name = &"FocusHighlight"
	_focus_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_highlight.top_level = true
	_focus_highlight.z_index = 100
	_focus_highlight.visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(2)
	style.border_color = Color(0.906, 0.698, 0.416, 0.9)  # brand gold #e7b26a
	style.set_corner_radius_all(8)
	_focus_highlight.add_theme_stylebox_override(&"panel", style)
	add_child(_focus_highlight)
	set_process(false)  # _process only runs while focus-navigating (see _input)


## Re-grab focus when the player first switches to keyboard/gamepad with nothing
## focused. The ring itself is positioned every frame in _process.
func _refresh_focus_highlight() -> void:
	if get_viewport().gui_get_focus_owner() == null and menu_stack.size():
		_focus_first_in(menu_stack.back())


## Glue the ring to the focused control every frame. Polling (rather than reacting
## once to gui_focus_changed) avoids reading a control's rect before its container
## has laid it out on a panel transition — which left the ring mispositioned until
## the next input event.
func _process(_delta: float) -> void:
	if _focus_highlight == null:
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if not _focus_nav or focus_owner == null or not is_ancestor_of(focus_owner):
		_focus_highlight.visible = false
		return
	var pad: float = 8.0  # gap between the control and the ring
	var rect: Rect2 = focus_owner.get_global_rect()
	_focus_highlight.global_position = rect.position - Vector2(pad, pad)
	_focus_highlight.size = rect.size + Vector2(pad * 2.0, pad * 2.0)
	_focus_highlight.visible = true


# --- Gateway theming -------------------------------------------------------
# A GatewayTheme resource per palette carries the whole look (its palette + the
# baked styleboxes + the backdrop). Assigning it to `theme` styles the entire
# subtree by inheritance, so we only (1) tag a few nodes with a theme_type_variation
# for their non-default look and (2) swap `theme` to change palette. No per-node
# style walking — a new screen can't fall off-palette. Authoring lives in the
# .tres themselves (inspector + "Rebuild styleboxes") or generate_gateway_themes.gd.

## Scan the themes folder into _themes / _theme_order (sorted by palette name).
func _load_gateway_themes() -> void:
	var dir: DirAccess = DirAccess.open(THEME_DIR)
	if dir == null:
		push_error("Gateway themes folder missing: " + THEME_DIR)
		return
	for file: String in dir.get_files():
		# Exported text resources are listed with a trailing ".remap"; load the
		# real .tres path (load() resolves the remap transparently).
		var file_name: String = file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var res: Resource = load(THEME_DIR + file_name)
		if res is GatewayTheme:
			# Key by filename slug so it always matches GatewayTheme.list_palettes()
			# (what the Settings dropdown stores), regardless of palette_name.
			var key: StringName = StringName(file_name.trim_prefix("gateway_").trim_suffix(".tres"))
			_themes[key] = res
			_theme_order.append(key)
	_theme_order.sort()


## Assign a palette: swap `theme` (restyles everything by inheritance), update the
## backdrop, retint the focus ring. Falls back to the first theme if unknown.
func _apply_gateway_theme(palette: StringName) -> void:
	if not _themes.has(palette):
		if _theme_order.is_empty():
			push_error("No gateway themes loaded.")
			return
		palette = _theme_order[0]
	current_theme = palette
	var gt: GatewayTheme = _themes[palette]
	theme = gt
	_apply_theme_background(gt.background)
	if _focus_highlight:
		var ring: StyleBoxFlat = _focus_highlight.get_theme_stylebox(&"panel") as StyleBoxFlat
		if ring:
			ring.border_color = Color(gt.active.r, gt.active.g, gt.active.b, 0.9)


## Scale the backdrop sprite to cover 960x540, centred.
func _apply_theme_background(tex: Texture2D) -> void:
	if tex == null:
		return
	$Background.texture = tex
	$Background.centered = true
	$Background.position = Vector2(480.0, 270.0)
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		var cover: float = maxf(960.0 / tex_size.x, 540.0 / tex_size.y)
		$Background.scale = Vector2(cover, cover)


## Pick the startup palette from the shared client settings: an explicit saved
## choice, a random one each launch (opt-in), or the default.
func _pick_startup_palette() -> StringName:
	if ClientState.settings.get_value(_SETTINGS_SECTION, _SETTING_RANDOMIZE) == true \
			and not _theme_order.is_empty():
		return _theme_order[randi() % _theme_order.size()]
	var saved: Variant = ClientState.settings.get_value(_SETTINGS_SECTION, _SETTING_PALETTE)
	if (saved is String or saved is StringName) and _themes.has(StringName(saved)):
		return StringName(saved)
	if _themes.has(DEFAULT_PALETTE):
		return DEFAULT_PALETTE
	return _theme_order[0] if not _theme_order.is_empty() else DEFAULT_PALETTE


## Live-apply a palette change made in the Settings menu so the gateway re-themes
## without a relaunch. (Persistence is handled by the setting widget itself.)
func _on_settings_changed(section: StringName, property: StringName, value: Variant) -> void:
	if section == _SETTINGS_SECTION and property == _SETTING_PALETTE and value is String:
		_apply_gateway_theme(StringName(value))


## Cycle palette — a debug / for-fun key only. Deliberately does NOT persist: the
## saved preference is owned by the Settings menu. The real palette choice for
## players is the [gateway] setting (default: randomize a new one each launch).
func _cycle_theme() -> void:
	if _theme_order.is_empty():
		return
	var i: int = _theme_order.find(current_theme)
	_apply_gateway_theme(_theme_order[(i + 1) % _theme_order.size()])


# --- Password fields ------------------------------------------------------

## Mask the password fields (they shipped unmasked) and give each panel a
## "Show password" toggle — important on mobile, where typing a password blind
## on a touch keyboard is a known drop-off point.
func _setup_password_fields() -> void:
	var login_pw: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	login_pw.secret = true
	_add_password_toggle($LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2, [login_pw])

	var create_pw: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	var create_pw_confirm: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer3/LineEdit
	create_pw.secret = true
	create_pw_confirm.secret = true
	_add_password_toggle(
		$CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer3,
		[create_pw, create_pw_confirm]
	)


func _add_password_toggle(into: Node, fields: Array[LineEdit]) -> void:
	var toggle: CheckBox = CheckBox.new()
	toggle.text = tr("SHOW_PASSWORD")
	toggle.toggled.connect(
		func(pressed: bool) -> void:
			for field: LineEdit in fields:
				field.secret = not pressed
	)
	into.add_child(toggle)


## A throwaway display name (character names aren't unique — Discord-style), for
## the "Random" dice next to the name field. Letters only, 2–3 syllables, so it
## always passes username validation.
func _random_character_name() -> String:
	var syllables: PackedStringArray = [
		"ar", "en", "th", "or", "el", "an", "ka", "ri", "mo", "lu", "ne", "sa",
		"to", "zi", "fae", "dra", "gor", "lyn", "mir", "nax", "veh", "sol", "kai",
	]
	var generated: String = ""
	for _n: int in randi_range(2, 3):
		generated += syllables[randi() % syllables.size()]
	return generated.capitalize()


# Helpers
func request_login(username: String, password: String) -> Dictionary:
	return await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayAPI.login(),
		{
			GatewayAPI.KEY_ACCOUNT_USERNAME: username,
			GatewayAPI.KEY_ACCOUNT_PASSWORD: password,
			GatewayAPI.KEY_CLIENT_VERSION: GatewayAPI.game_version(),
		}
	)

func request_enter_world() -> Dictionary:
	return await do_request(
			HTTPClient.Method.METHOD_POST,
			GatewayAPI.world_enter(),
			{
				GatewayAPI.KEY_TOKEN_ID: session_id,
				GatewayAPI.KEY_ACCOUNT_USERNAME: account_name,
				GatewayAPI.KEY_WORLD_ID: current_world_id,
				GatewayAPI.KEY_CHAR_ID: current_character_id
			}
		)


func prepare_character_creation_menu() -> void:
	_skin_preview = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer2/CenterContainer/Control/AnimatedSprite2D
	_skin_preview.play(&"run")

	# Replace the tiny-icon grid with a Prev / name / Next cycler. The big centre
	# preview is the visual, so the chosen character shows LARGE instead of as 8
	# small icons.
	var grid: GridContainer = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/VBoxContainer
	for child: Node in grid.get_children():
		child.queue_free()
	grid.columns = 3

	var prev: Button = Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44.0, 44.0)
	prev.add_theme_font_size_override(&"font_size", 22)
	prev.pressed.connect(_cycle_skin.bind(-1))

	_skin_name_label = Label.new()
	_skin_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skin_name_label.custom_minimum_size = Vector2(110.0, 44.0)

	var next: Button = Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44.0, 44.0)
	next.add_theme_font_size_override(&"font_size", 22)
	next.pressed.connect(_cycle_skin.bind(1))

	grid.add_child(prev)
	grid.add_child(_skin_name_label)
	grid.add_child(next)

	_apply_skin(0)  # show the first skin in the preview

	# Enable the (scene-hidden) "Random" dice next to the name field.
	var name_edit: LineEdit = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer2/LineEdit
	var random_button: Button = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer2/Button
	random_button.visible = true
	random_button.pressed.connect(
		func() -> void:
			name_edit.text = _random_character_name()
	)


## Cycle the starter skin by +1 / -1 (wraps around the roster).
func _cycle_skin(delta: int) -> void:
	if PLAYER_SKINS.is_empty():
		return
	_apply_skin(wrapi(_skin_index + delta, 0, PLAYER_SKINS.size()))


## Apply a skin by index — set selected_skin_id, update the preview + name label.
func _apply_skin(index: int) -> void:
	if index < 0 or index >= PLAYER_SKINS.size():
		return
	var slug: String = PLAYER_SKINS[index]
	var frames: SpriteFrames = ContentRegistryHub.load_by_slug(&"sprites", slug) as SpriteFrames
	if not frames:
		return
	_skin_index = index
	selected_skin_id = ContentRegistryHub.id_from_slug(&"sprites", slug)
	if selected_skin_id == 0:
		selected_skin_id = 1
	if _skin_preview:
		_skin_preview.sprite_frames = frames
		_skin_preview.play(&"run")
	if _skin_name_label:
		_skin_name_label.text = slug.capitalize()


# Ideally we must not save credentials locally even if crypted,
# saving a temporary token given by the server is the way. 
func try_auto_login() -> bool:
	# Load the saved session FIRST. A first-time player (no token) goes straight
	# to the main menu — no spinner, no boot delay, nothing to wait on.
	var file_path: String = "user://%ssession.dat" % local_id
	var refresh_token: String = load_refresh_token(file_path)
	if refresh_token.is_empty():
		return false

	var username: String = refresh_token.get_slice("\n", 0)
	var password: String = refresh_token.get_slice("\n", 1)

	$MainPanel.hide()
	popup_panel.display_waiting_popup()

	var response: Dictionary = await request_login(username, password)

	# In the editor, "Run Multiple Instances" boots gateway/master/world AND the
	# client all at once, so the gateway may not be listening yet on the first
	# try. Retry briefly on a pure connection failure (not on a real rejection
	# like bad credentials). Exported clients talk to an always-on remote gateway,
	# so OS.has_feature("editor") is false and they skip the retries entirely.
	var attempts: int = 0
	while OS.has_feature("editor") and GatewayError.is_connection_error(response) and attempts < 20:
		attempts += 1
		await get_tree().create_timer(0.25).timeout
		response = await request_login(username, password)

	if response.has("error"):
		# Stale or failed auto-login (saved password no longer valid, server
		# unreachable, …). Fall back to the main menu silently — greeting a
		# returning player with an error popup on launch is a bad first beat.
		# They can still log in manually from there.
		return false
	handle_success_login(response)
	return true


# Can be changed / randomized each build
const LOCAL_PASS: String = "LOCAL_PASSWORD"
func save_refresh_token(token: String, file_path: String) -> void:
	var file: FileAccess = FileAccess.open_encrypted_with_pass(file_path, FileAccess.WRITE, LOCAL_PASS)
	if file:
		file.store_string(token)
		file.close()
	else:
		printerr(error_string(FileAccess.get_open_error()))


func load_refresh_token(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var file: FileAccess = FileAccess.open_encrypted_with_pass(file_path, FileAccess.READ, LOCAL_PASS)
	if not file:
		printerr(error_string(FileAccess.get_open_error()))
		return ""
	var token: String = file.get_as_text()
	file.close()
	return token
