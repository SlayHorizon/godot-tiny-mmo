extends Control
## Leaderboard panel: pick a domain (PvP / PvE / Guilds / Level / Arena), then a
## time period when relevant, see the top 20. Two-step picker keeps the UI light
## instead of a flat dropdown of 10 entries.
##
## The shell (header / two empty button rows / scroll) lives in the .tscn for
## editor auditing; this script just populates the two button rows from DOMAINS
## below and wires clicks. Add or rename a domain by editing DOMAINS only.

const ROW_LIMIT: int = 20
## A domain is a category of board. Domains with an empty `periods` list have
## no time-window choice (e.g. Level is naturally lifetime). The `board_id` on
## each period (or on the domain itself for period-less ones) is what gets sent
## to the server's leaderboard.top handler.
const DOMAINS: Array = [
	{
		"id": "pvp", "label": "PvP",
		"periods": [
			{"id": "pvp_week",  "label": "This Week"},
			{"id": "pvp_day",   "label": "Today"},
			{"id": "pvp_total", "label": "All-Time"},
		],
	},
	{
		"id": "pve", "label": "PvE",
		"periods": [
			{"id": "pve_week",  "label": "This Week"},
			{"id": "pve_day",   "label": "Today"},
			{"id": "pve_total", "label": "All-Time"},
		],
	},
	{
		"id": "guilds", "label": "Guilds",
		"periods": [
			{"id": "glory_seasonal", "label": "Seasonal"},
			{"id": "glory_eternal",  "label": "Eternal"},
		],
	},
	{"id": "arena", "label": "Arena", "board_id": "arena_wins", "periods": []},
	{"id": "level", "label": "Level", "board_id": "level",      "periods": []},
]

@export var domain_buttons_box: HBoxContainer
@export var period_buttons_box: HBoxContainer
@export var period_row: Control # Hidden when the selected domain has no periods.
@export var refresh_button: Button
@export var close_button: Button
@export var status_label: Label
@export var entries_box: VBoxContainer

var _current_domain_idx: int = 0
var _current_period_idx: int = 0


func _ready() -> void:
	for i: int in DOMAINS.size():
		var btn: Button = Button.new()
		btn.text = str(DOMAINS[i]["label"])
		btn.toggle_mode = true
		btn.pressed.connect(_on_domain_pressed.bind(i))
		domain_buttons_box.add_child(btn)
	refresh_button.pressed.connect(_request)
	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	_select_domain(0)


func _on_visibility_changed() -> void:
	if visible:
		_request()


func _on_domain_pressed(idx: int) -> void:
	_select_domain(idx)


func _on_period_pressed(idx: int) -> void:
	_current_period_idx = idx
	_paint_selection(period_buttons_box, idx)
	_request()


## Switch domain, rebuild the period row to match, default to the first period.
func _select_domain(idx: int) -> void:
	_current_domain_idx = idx
	_current_period_idx = 0
	_paint_selection(domain_buttons_box, idx)

	for child: Node in period_buttons_box.get_children():
		child.queue_free()

	var periods: Array = DOMAINS[idx].get("periods", [])
	period_row.visible = not periods.is_empty()
	for i: int in periods.size():
		var btn: Button = Button.new()
		btn.text = str(periods[i]["label"])
		btn.toggle_mode = true
		btn.pressed.connect(_on_period_pressed.bind(i))
		period_buttons_box.add_child(btn)
	if not periods.is_empty():
		_paint_selection(period_buttons_box, 0)
	_request()


## Visually mark which button in a row is the active one.
func _paint_selection(box: HBoxContainer, idx: int) -> void:
	for i: int in box.get_child_count():
		var btn: Button = box.get_child(i) as Button
		if btn == null:
			continue
		btn.button_pressed = (i == idx)


## Resolve the current selection to a server board_id.
func _current_board_id() -> String:
	var domain: Dictionary = DOMAINS[_current_domain_idx]
	var periods: Array = domain.get("periods", [])
	if periods.is_empty():
		return str(domain.get("board_id", ""))
	return str(periods[_current_period_idx]["id"])


func _request() -> void:
	var board: String = _current_board_id()
	if board.is_empty():
		return
	status_label.text = "Loading..."
	Client.request_data(
		&"leaderboard.top",
		_apply_response,
		{"board": board, "limit": ROW_LIMIT},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _apply_response(response: Dictionary) -> void:
	for child: Node in entries_box.get_children():
		child.queue_free()

	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		status_label.text = "No entries yet — go earn some glory."
		return
	status_label.text = "Top %d" % entries.size()

	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)

		var rank: Label = Label.new()
		rank.text = "%d." % (i + 1)
		rank.custom_minimum_size = Vector2(40, 0)
		row.add_child(rank)

		var name_lbl: Label = Label.new()
		name_lbl.text = str(entry.get("name", "?"))
		name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var score_lbl: Label = Label.new()
		score_lbl.text = str(entry.get("score", 0))
		row.add_child(score_lbl)

		entries_box.add_child(row)
