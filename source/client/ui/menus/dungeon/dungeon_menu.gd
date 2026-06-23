extends MenuShell
## Full-screen dungeon manager. Opened by clicking a DungeonMaster
## (open_menu_requested(&"dungeon", master_id)). LEFT: the dungeon's info (from its
## DungeonResource). RIGHT: three header tabs —
##   Party       public queue (its roster) + Hard toggle + Join / Solo / Start
##   Private     create a code-only room or join one by its 2-digit code; once in,
##               the roster + Start (leader) / Leave
##   Leaderboard this dungeon's fastest Hard clears
## A player is in at most one lobby — the server cross-evicts (public queue vs room).

var _station: String = "" # the station's node name (auto id; no manual master_id)
var _dungeon_name: String = "Dungeon" # instance_name, for the leaderboard board id
var _master_name: String = "Dungeon"
var _queued: bool = false
var _hard: bool = false
var _members: Array = []
var _capacity: int = 4
var _active_tab: StringName = &"party"
## The private room we're in (snapshot), or empty when not in one.
var _room: Dictionary = {}

var _info_box: VBoxContainer
var _right: PanelContainer
var _tab_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	build_shell("Dungeon", null, true)
	Client.subscribe(&"dungeon.lobby.update", _on_lobby_update)
	Client.subscribe(&"dungeon.room.update", _on_room_update)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func open(station: String) -> void:
	_station = station
	_queued = false
	_active_tab = &"party"
	_refresh()


# --- layout ----------------------------------------------------------------

func _build_layout() -> void:
	for tab: Array in [["party", "Public"], ["private", "Private"], ["leaderboard", "Leaderboard"]]:
		var btn: Button = Button.new()
		btn.text = str(tab[1])
		btn.theme_type_variation = &"SectionTab"
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 32)
		btn.pressed.connect(_select_tab.bind(StringName(tab[0])))
		header_center.add_child(btn)
		_tab_buttons[StringName(tab[0])] = btn

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 14)
	content.add_child(hbox)

	# Left: dungeon info only (rosters live in their tabs, so no double party).
	_info_box = VBoxContainer.new()
	_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_box.add_theme_constant_override(&"separation", 6)
	hbox.add_child(_info_box)

	# Right: the active tab's panel.
	_right = PanelContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.size_flags_stretch_ratio = 1.4
	hbox.add_child(_right)


# --- data ------------------------------------------------------------------

func _refresh() -> void:
	if _info_box == null:
		return
	Client.request_data(
		&"dungeon.info", _apply_state, {"station": _station},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _apply_state(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		Toaster.toast({
			"too_far": "You're too far from the dungeon.",
			"no_master": "Dungeon not found.",
			"no_dungeon": "This station has no dungeon set.",
			"in_run": "You're already in a dungeon.",
			"full": "The party is full.",
		}.get(str(response.get("reason", "")), "Dungeon unavailable."))
		hide()
		return
	if bool(response.get("started", false)):
		hide()
		return
	if response.has("queued"):
		_queued = bool(response["queued"])
	_master_name = str(response.get("master_name", _master_name))
	_capacity = int(response.get("capacity", _capacity))
	_members = response.get("members", [])
	var info: Dictionary = response.get("dungeon", {})
	_dungeon_name = str(info.get("name", _master_name))
	set_title(_master_name)
	_render_info(info)
	_render_active_tab()


func _render_info(info: Dictionary) -> void:
	# Pretty name is in the title bar; the panel leads with the at-a-glance stats.
	for child: Node in _info_box.get_children():
		child.queue_free()
	var rec: int = int(info.get("recommended_level", 0))
	if rec > 0:
		_info_line("Recommended level %d" % rec, Color(0.8, 0.85, 1.0), 13)
	var desc: String = str(info.get("description", ""))
	if not desc.is_empty():
		_info_line(desc, Color(0.82, 0.84, 0.9), 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_line("Reward: %s" % str(info.get("reward", "—")), Color(0.8, 0.9, 0.8), 12)
	_info_line("Hard: %s" % str(info.get("hard_reward", "—")), Color(0.86, 0.7, 0.5), 12)


func _on_lobby_update(payload: Dictionary) -> void:
	if not visible or str(payload.get("station", "")) != _station:
		return
	_capacity = int(payload.get("capacity", _capacity))
	_members = payload.get("members", [])
	if _active_tab == &"party":
		_render_active_tab()


# --- tabs ------------------------------------------------------------------

func _select_tab(tab: StringName) -> void:
	_active_tab = tab
	for key: StringName in _tab_buttons:
		_tab_buttons[key].button_pressed = (key == tab)
	_render_active_tab()
	if tab == &"party":
		_refresh() # pull a fresh public roster each time the tab is opened


## Rebuild the right panel for the current tab (no re-request — callers update the
## backing state first). Kept separate from _select_tab so the public-tab refresh
## doesn't loop.
func _render_active_tab() -> void:
	if _right == null:
		return
	for child: Node in _right.get_children():
		child.queue_free()
	match _active_tab:
		&"leaderboard":
			_build_leaderboard_panel()
		&"private":
			_build_private_panel()
		_:
			_build_party_panel()


func _build_party_panel() -> void:
	var vbox: VBoxContainer = _panel_body()
	_add_roster(vbox, "Public party", _members, _capacity, true)
	var note: Label = Label.new()
	note.text = "Normal mode — drop in with anyone. (Hard mode lives in Private rooms.)"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(note)
	vbox.add_child(HSeparator.new())

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	vbox.add_child(buttons)
	if _queued:
		buttons.add_child(_action_button("Start", _on_start))
		buttons.add_child(_action_button("Leave", _on_leave))
	else:
		buttons.add_child(_action_button("Join", _on_join))
		buttons.add_child(_action_button("Solo", _on_solo))


func _build_private_panel() -> void:
	var vbox: VBoxContainer = _panel_body()
	if _room.is_empty():
		var blurb: Label = Label.new()
		blurb.text = "Make a private room and share its code, or join one by code."
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.modulate = Color(1, 1, 1, 0.7)
		vbox.add_child(blurb)

		var create_row: HBoxContainer = HBoxContainer.new()
		create_row.add_theme_constant_override(&"separation", 8)
		vbox.add_child(create_row)
		var hard_chk: CheckButton = CheckButton.new()
		hard_chk.text = "Hard"
		hard_chk.button_pressed = _hard
		hard_chk.toggled.connect(func(on: bool) -> void: _hard = on)
		create_row.add_child(hard_chk)
		create_row.add_child(_action_button("Create Room", func() -> void: _room_request("create", {"hard": _hard})))

		vbox.add_child(HSeparator.new())
		var join_row: HBoxContainer = HBoxContainer.new()
		join_row.add_theme_constant_override(&"separation", 6)
		vbox.add_child(join_row)
		var code_edit: LineEdit = LineEdit.new()
		code_edit.placeholder_text = "Code"
		code_edit.max_length = DungeonService.ROOM_CODE_LEN
		code_edit.custom_minimum_size = Vector2(90, 0)
		join_row.add_child(code_edit)
		join_row.add_child(_action_button("Join by code", func() -> void: _room_request("join_code", {"code": code_edit.text})))
		return

	# In a room.
	var code_label: Label = Label.new()
	code_label.text = "Room code:  %s" % str(_room.get("code", "—"))
	code_label.add_theme_font_size_override(&"font_size", 18)
	code_label.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.55))
	vbox.add_child(code_label)
	if bool(_room.get("hard", false)):
		_info_into(vbox, "Hard Mode", Color(0.86, 0.7, 0.5))
	_add_roster(vbox, "Members", _room.get("members", []), int(_room.get("capacity", 4)), false)
	vbox.add_child(HSeparator.new())
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	vbox.add_child(buttons)
	if bool(_room.get("is_leader", false)):
		buttons.add_child(_action_button("Start", func() -> void: _room_request("start")))
	buttons.add_child(_action_button("Leave", func() -> void: _room_request("leave")))


func _build_leaderboard_panel() -> void:
	var vbox: VBoxContainer = _panel_body()
	var heading: Label = Label.new()
	heading.text = "Fastest Clears (Hard)"
	heading.add_theme_font_size_override(&"font_size", 15)
	heading.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.55))
	vbox.add_child(heading)
	var status: Label = Label.new()
	status.text = "Loading…"
	status.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(status)
	Client.request_data(
		&"leaderboard.top",
		func(response: Dictionary) -> void: _render_leaderboard(vbox, status, response),
		{"board": "dungeon:" + _dungeon_name, "limit": 10},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _render_leaderboard(vbox: VBoxContainer, status: Label, response: Dictionary) -> void:
	if not is_instance_valid(vbox):
		return
	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		status.text = "No clears yet — be the first."
		return
	status.text = ""
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var row: Label = Label.new()
		var seconds: int = int(entry.get("score", 0))
		@warning_ignore("integer_division")
		row.text = "%d. %s — %d:%02d" % [i + 1, str(entry.get("name", "?")), seconds / 60, seconds % 60]
		if i < 3:
			row.add_theme_color_override(&"font_color", [Color(1.0, 0.84, 0.3), Color(0.8, 0.82, 0.88), Color(0.82, 0.56, 0.35)][i])
		vbox.add_child(row)


# --- requests --------------------------------------------------------------

func _send(action: String) -> void:
	# Public party is always Normal — Hard is private-rooms only (no griefing noobs
	# into hardmode from a public Start).
	Client.request_data(
		&"dungeon.queue", _apply_state,
		{"station": _station, "action": action, "hard": false},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_join() -> void:
	_send("join")


func _on_leave() -> void:
	_queued = false
	_send("leave")


func _on_start() -> void:
	_send("start")


func _on_solo() -> void:
	_send("solo")


func _room_request(action: String, extra: Dictionary = {}) -> void:
	var args: Dictionary = {"station": _station, "action": action}
	args.merge(extra)
	Client.request_data(
		&"dungeon.rooms", _on_room_response, args,
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_room_response(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		Toaster.toast({
			"full": "Room is full.",
			"no_room": "No room with that code.",
			"in_run": "You're already in a dungeon.",
			"too_far": "You're too far from the dungeon.",
			"not_leader": "Only the leader can start.",
		}.get(str(response.get("reason", "")), "Couldn't do that."))
		return
	if bool(response.get("started", false)):
		hide()
		return
	if bool(response.get("left", false)):
		_room = {}
	elif response.has("room"):
		_room = response["room"]
	if _active_tab == &"private":
		_render_active_tab()


## Server push: a room we're in changed (member joined/left), closed, or started.
func _on_room_update(payload: Dictionary) -> void:
	if not visible:
		return
	if bool(payload.get("started", false)):
		hide()
		return
	if bool(payload.get("closed", false)):
		_room = {}
	else:
		_room = payload
	if _active_tab == &"private":
		_render_active_tab()


# --- helpers ---------------------------------------------------------------

## A padded VBox filling the right panel — the body every tab builds into.
func _panel_body() -> VBoxContainer:
	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 14)
	pad.add_theme_constant_override(&"margin_right", 14)
	pad.add_theme_constant_override(&"margin_top", 12)
	pad.add_theme_constant_override(&"margin_bottom", 12)
	_right.add_child(pad)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override(&"separation", 10)
	pad.add_child(vbox)
	return vbox


## Roster block: "<title>  (N/cap)" + a row per member, plus empty "—" slots when
## [param show_empty] (the public queue shows them; a room doesn't).
func _add_roster(vbox: VBoxContainer, title: String, members: Array, capacity: int, show_empty: bool) -> void:
	var header: Label = Label.new()
	header.text = "%s  (%d/%d)" % [title, members.size(), capacity]
	header.add_theme_font_size_override(&"font_size", 14)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	vbox.add_child(header)
	for member: Variant in members:
		var row: Label = Label.new()
		row.text = "• " + str(member)
		vbox.add_child(row)
	if show_empty:
		for _i: int in range(members.size(), capacity):
			var slot: Label = Label.new()
			slot.text = "• —"
			slot.modulate.a = 0.35
			vbox.add_child(slot)


func _info_line(text: String, color: Color, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	_info_box.add_child(label)
	return label


func _info_into(vbox: VBoxContainer, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", color)
	vbox.add_child(label)


func _action_button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 40)
	b.pressed.connect(callback)
	return b
