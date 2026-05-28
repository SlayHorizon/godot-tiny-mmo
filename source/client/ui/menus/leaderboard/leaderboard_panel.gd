extends Control
## Minimal leaderboard panel. Self-bootstraps its UI (board picker, refresh
## button, scrollable entries list) so no .tscn authoring is needed — drop a
## Control with this script attached anywhere in the HUD/menu tree.
##
## Boards are listed in BOARDS below; add/remove rows there to expose more or
## fewer rankings without touching anything else.

const BOARDS: Array = [
	{"id": "pvp_week",       "label": "PvP Kills — This Week"},
	{"id": "pvp_day",        "label": "PvP Kills — Today"},
	{"id": "pvp_total",      "label": "PvP Kills — All Time"},
	{"id": "pve_week",       "label": "PvE Kills — This Week"},
	{"id": "pve_day",        "label": "PvE Kills — Today"},
	{"id": "pve_total",      "label": "PvE Kills — All Time"},
	{"id": "level",          "label": "Highest Level"},
	{"id": "glory_seasonal", "label": "Guild — Seasonal Glory"},
	{"id": "glory_eternal",  "label": "Guild — Eternal Glory"},
]

const ROW_LIMIT: int = 20

var _board_picker: OptionButton
var _entries_box: VBoxContainer
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_request(BOARDS[0]["id"])


func _build_ui() -> void:
	# Outer panel to give the floating UI a background + padding.
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 6)
	panel.add_child(vbox)

	# Header row: title + refresh button + board picker.
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	vbox.add_child(header)

	var title: Label = Label.new()
	title.text = "Leaderboard"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)

	_board_picker = OptionButton.new()
	for i in BOARDS.size():
		_board_picker.add_item(str(BOARDS[i]["label"]), i)
	_board_picker.item_selected.connect(_on_board_changed)
	header.add_child(_board_picker)

	var refresh: Button = Button.new()
	refresh.text = "↻"
	refresh.tooltip_text = "Refresh"
	refresh.pressed.connect(func(): _request(BOARDS[_board_picker.selected]["id"]))
	header.add_child(refresh)

	_status_label = Label.new()
	_status_label.text = "Loading..."
	_status_label.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(_status_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(320, 360)
	vbox.add_child(scroll)

	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override(&"separation", 2)
	scroll.add_child(_entries_box)


func _on_board_changed(idx: int) -> void:
	_request(BOARDS[idx]["id"])


func _request(board: String) -> void:
	_status_label.text = "Loading..."
	Client.request_data(
		&"leaderboard.top",
		_apply_response,
		{"board": board, "limit": ROW_LIMIT},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _apply_response(response: Dictionary) -> void:
	# Clear previous rows.
	for child: Node in _entries_box.get_children():
		child.queue_free()

	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		_status_label.text = "No entries yet — go earn some glory."
		return
	_status_label.text = "Top %d" % entries.size()

	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)

		var rank: Label = Label.new()
		rank.text = "%d." % (i + 1)
		rank.custom_minimum_size = Vector2(32, 0)
		row.add_child(rank)

		var name_lbl: Label = Label.new()
		name_lbl.text = str(entry.get("name", "?"))
		name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var score_lbl: Label = Label.new()
		score_lbl.text = str(entry.get("score", 0))
		row.add_child(score_lbl)

		_entries_box.add_child(row)
