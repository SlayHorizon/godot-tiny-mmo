extends MenuShell
## Leaderboard — split view (quests/jobs style): a list of board domains on the
## left, and on the right the selected board's period toggles (This Week / Today
## / All-Time, where relevant) above the ranked entries. Player rows are
## clickable to open that player's profile.
##
## Add or rename a board by editing DOMAINS only. Each domain's period `id` (or
## the domain's `board_id` when period-less) is the board sent to the server's
## leaderboard.top handler.

const ROW_LIMIT: int = 20
## Reuse a fetched board for this long before hitting the server again (open + tab-switch use the cache;
## the Reload button forces a fresh fetch). Leaderboards don't change second-to-second, so this trims
## redundant traffic without feeling stale.
const CACHE_TTL_S: float = 30.0
## Categories group the board list on the left (like the jobs panel).
const CATEGORIES: Array = [
	{"id": "combat", "label": "Combat"},
	{"id": "progression", "label": "Progression"},
	{"id": "guild", "label": "Guild"},
	{"id": "dungeon", "label": "Dungeons"},
]
const DOMAINS: Array = [
	{
		"id": "pvp", "label": "PvP Kills", "category": "combat",
		"periods": [
			{"id": "pvp_total", "label": "All-Time"},
			{"id": "pvp_week",  "label": "This Week"},
			# Daily tab hidden: small player base makes it look empty. Uncomment to restore.
			# {"id": "pvp_day", "label": "Today"},
		],
	},
	{
		"id": "pve", "label": "PvE Kills", "category": "combat",
		"periods": [
			{"id": "pve_total", "label": "All-Time"},
			{"id": "pve_week",  "label": "This Week"},
			# Daily tab hidden: small player base makes it look empty. Uncomment to restore.
			# {"id": "pve_day", "label": "Today"},
		],
	},
	{
		"id": "guilds", "label": "Guild Glory", "category": "guild",
		"periods": [
			{"id": "glory_seasonal", "label": "Seasonal"},
			{"id": "glory_eternal",  "label": "Eternal"},
		],
	},
	{"id": "arena", "label": "Arena Wins", "category": "combat", "board_id": "arena_wins", "periods": []},
	{"id": "level", "label": "Highest Level", "category": "progression", "board_id": "level", "periods": []},
	{"id": "gold",  "label": "Richest", "category": "progression", "board_id": "gold", "periods": []},
	# Dungeon fastest-clear boards (Hard only). board_id is "dungeon:<instance_name>";
	# scores are SECONDS shown as m:ss (lower is better). One entry per ranked dungeon.
	{"id": "dungeon_main", "label": "Fastest Clear (Hard)", "category": "dungeon", "board_id": "dungeon:Dungeon", "periods": []},
]

const RANK_COLORS: Dictionary = {
	1: Color(1.0, 0.84, 0.3),    # gold
	2: Color(0.8, 0.82, 0.88),   # silver
	3: Color(0.82, 0.56, 0.35),  # bronze
}

var _domain_list: VBoxContainer
var _board_title: Label
var _period_bar: HBoxContainer
var _status_label: Label
var _entries_box: VBoxContainer
var _entries_scroll: ScrollContainer

var _domain_idx: int
var _period_idx: int
## Keyed by DOMAINS index (the list is built grouped by category, so a plain
## array's positions wouldn't line up with domain indices).
var _domain_buttons: Dictionary[int, Button]
var _period_buttons: Array[Button]
## board_id -> {"data": Dictionary, "time": float unix-seconds}. Survives menu re-opens (the menu
## instance persists), so rapid open/close + tab toggling reuse recent results instead of re-fetching.
var _cache: Dictionary = {}


func _ready() -> void:
	build_shell("Leaderboard", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_request())
	_select_domain(0)


func _build_layout() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 12)
	content.add_child(hbox)

	# Left: board domain list.
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.7
	hbox.add_child(left_scroll)

	_domain_list = VBoxContainer.new()
	_domain_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_domain_list.add_theme_constant_override(&"separation", 4)
	left_scroll.add_child(_domain_list)

	for cat: Dictionary in CATEGORIES:
		var domain_indices: Array = []
		for i: int in DOMAINS.size():
			if str(DOMAINS[i].get("category", "")) == str(cat["id"]):
				domain_indices.append(i)
		if domain_indices.is_empty():
			continue
		_domain_list.add_child(_make_section_header(str(cat["label"])))
		for i: int in domain_indices:
			var btn: Button = Button.new()
			btn.text = str(DOMAINS[i]["label"])
			btn.toggle_mode = true
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(0, 40)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_select_domain.bind(i))
			_domain_list.add_child(btn)
			_domain_buttons[i] = btn

	DragScroll.enable(left_scroll) # touch/mouse drag-to-scroll the domain list

	# Right: title + period toggles + entries.
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.5
	right_col.add_theme_constant_override(&"separation", 8)
	hbox.add_child(right_col)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	right_col.add_child(header)

	_board_title = Label.new()
	_board_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_title.add_theme_font_size_override(&"font_size", 18)
	_board_title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	_board_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_board_title)

	var refresh: Button = Button.new()
	refresh.text = "Reload"
	refresh.tooltip_text = "Fetch the latest standings now"
	refresh.pressed.connect(_request.bind(true))
	header.add_child(refresh)

	_period_bar = HBoxContainer.new()
	_period_bar.add_theme_constant_override(&"separation", 4)
	right_col.add_child(_period_bar)

	_status_label = Label.new()
	_status_label.modulate = Color(1, 1, 1, 0.6)
	right_col.add_child(_status_label)

	_entries_scroll = ScrollContainer.new()
	_entries_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_entries_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(_entries_scroll)

	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override(&"separation", 4)
	_entries_scroll.add_child(_entries_box)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _select_domain(idx: int) -> void:
	_domain_idx = idx
	_period_idx = 0
	for key: int in _domain_buttons:
		_domain_buttons[key].button_pressed = (key == idx)

	_board_title.text = str(DOMAINS[idx]["label"])

	for child: Node in _period_bar.get_children():
		child.queue_free()
	_period_buttons.clear()

	var periods: Array = DOMAINS[idx].get("periods", [])
	_period_bar.visible = not periods.is_empty()
	for i: int in periods.size():
		var btn: Button = Button.new()
		btn.text = str(periods[i]["label"])
		btn.theme_type_variation = &"SectionTab"
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_period.bind(i))
		_period_bar.add_child(btn)
		_period_buttons.append(btn)

	_request()


func _select_period(idx: int) -> void:
	_period_idx = idx
	for i: int in _period_buttons.size():
		_period_buttons[i].button_pressed = (i == idx)
	_request()


func _current_board_id() -> String:
	var domain: Dictionary = DOMAINS[_domain_idx]
	var periods: Array = domain.get("periods", [])
	if periods.is_empty():
		return str(domain.get("board_id", ""))
	return str(periods[_period_idx]["id"])


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

## Fetch the current board, or reuse a recent cached result. [param force] (the Reload button) always
## re-fetches. Open + tab-switches route through here too, so a fresh cache means no server hit on re-open.
func _request(force: bool = false) -> void:
	var board: String = _current_board_id()
	if board.is_empty():
		return
	if not force and _cache.has(board):
		var entry: Dictionary = _cache[board]
		if Time.get_unix_time_from_system() - float(entry["time"]) < CACHE_TTL_S:
			_apply_response(entry["data"])
			return
	_status_label.text = "Loading..."
	Client.request_data(
		&"leaderboard.top",
		_on_fetched.bind(board),
		{"board": board, "limit": ROW_LIMIT},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


## Cache the fetched board, then render it only if it's still the one on screen (the player may have
## switched boards while the request was in flight).
func _on_fetched(response: Dictionary, board: String) -> void:
	_cache[board] = {"data": response, "time": Time.get_unix_time_from_system()}
	if board == _current_board_id():
		_apply_response(response)


func _apply_response(response: Dictionary) -> void:
	for child: Node in _entries_box.get_children():
		child.queue_free()

	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		_status_label.text = "No entries yet — go earn some glory."
		return
	_status_label.text = "Top %d" % entries.size()

	var is_player_board: bool = str(DOMAINS[_domain_idx]["id"]) != "guilds"
	var is_time: bool = _current_board_id().begins_with("dungeon:") # score is seconds, show m:ss
	for i: int in entries.size():
		_entries_box.add_child(_make_entry_row(i + 1, entries[i], is_player_board, is_time))
	DragScroll.enable(_entries_scroll) # touch/mouse drag-to-scroll the ranked entries


## A ranked row: rank (top-3 medal-coloured) + name + score. Player rows are
## clickable: a player row opens that player's profile, a guild row opens that
## guild in the guild menu (even if you're not a member).
func _make_entry_row(rank_num: int, entry: Dictionary, is_player_board: bool, is_time: bool = false) -> Control:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var rank_label: Label = Label.new()
	rank_label.text = "%d" % rank_num
	rank_label.custom_minimum_size = Vector2(36, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if RANK_COLORS.has(rank_num):
		rank_label.add_theme_color_override(&"font_color", RANK_COLORS[rank_num])
		rank_label.add_theme_font_size_override(&"font_size", 16)
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(rank_label)

	var name_label: Label = Label.new()
	name_label.text = str(entry.get("name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	var score_label: Label = Label.new()
	score_label.text = _format_score(int(entry.get("score", 0)), is_time)
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(score_label)

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.add_child(hbox)
	if is_player_board:
		button.pressed.connect(_on_entry_pressed.bind(int(entry.get("id", 0))))
	else:
		button.pressed.connect(_on_guild_entry_pressed.bind(str(entry.get("name", ""))))
	return button


## A count board shows the raw number; a time board (dungeon clear) shows m:ss.
func _format_score(score: int, is_time: bool) -> String:
	if not is_time:
		return str(score)
	@warning_ignore("integer_division")
	return "%d:%02d" % [score / 60, score % 60]


func _on_entry_pressed(player_id: int) -> void:
	if player_id <= 0:
		return
	hide()
	ClientState.player_profile_requested.emit(player_id)


func _on_guild_entry_pressed(guild_name: String) -> void:
	if guild_name.is_empty():
		return
	hide()
	ClientState.open_menu_requested.emit(&"guild", guild_name)


func _make_section_header(text: String) -> Label:
	var header: Label = Label.new()
	header.text = text
	header.add_theme_font_size_override(&"font_size", 13)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	return header
