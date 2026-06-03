extends PanelContainer
## Read-only stat readout for the Character → Stats tab. Builds its own
## two-column grid (stat name / value) so it fills the left half of the tab
## and stays legible, and live-updates when the watched player's stats change.

## [label, color, primary Stat key, optional secondary key for "cur / max"].
## Secondary == null → single value. Strings are used for non-enum keys.
const _ROWS: Array = [
	["Health", Color("#3de600"), Stat.HEALTH, Stat.HEALTH_MAX],
	["Mana", Color("#33b5e5"), Stat.MANA_MAX, null],
	["Attack", Color("#fc7f03"), Stat.AD, null],
	["Armor", Color("#d8a657"), Stat.ARMOR, null],
	["Magic", Color("#a67ffb"), Stat.AP, null],
	["Magic Res", Color("#a67ffb"), Stat.MR, null],
	["Move Speed", Color("#dbd802"), Stat.MOVE_SPEED, null],
	["Tenacity", Color("#7dc94f"), &"tenacity", null],
]

var observed_stats: StatsComponent.Stats

var _grid: GridContainer


func _ready() -> void:
	_build_layout()
	_try_watch()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _try_watch())


func _build_layout() -> void:
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	add_child(pad)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 10)
	pad.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Stats"
	title.add_theme_color_override(&"font_color", Color(1, 0.9, 0.55))
	title.add_theme_font_size_override(&"font_size", 16)
	vbox.add_child(title)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", 16)
	_grid.add_theme_constant_override(&"v_separation", 8)
	vbox.add_child(_grid)


func _try_watch() -> void:
	if ClientState.local_player:
		watch_stats(ClientState.local_player.stats_component.stats)


func watch_stats(stats: StatsComponent.Stats) -> void:
	if observed_stats and observed_stats.stat_changed.is_connected(_on_stats_changed):
		observed_stats.stat_changed.disconnect(_on_stats_changed)

	observed_stats = stats
	if observed_stats:
		observed_stats.stat_changed.connect(_on_stats_changed)

	redraw()


func _on_stats_changed(_stat_name: StringName, _value: float) -> void:
	redraw()


func redraw() -> void:
	if _grid == null or not observed_stats:
		return

	for child in _grid.get_children():
		child.queue_free()

	for row: Array in _ROWS:
		var label_text: String = row[0]
		var color: Color = row[1]
		var primary: Variant = row[2]
		var secondary: Variant = row[3]

		var name_label: Label = Label.new()
		name_label.text = label_text
		name_label.add_theme_font_size_override(&"font_size", 15)
		name_label.add_theme_color_override(&"font_color", Color(0.78, 0.82, 0.9))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(name_label)

		var value_label: Label = Label.new()
		if secondary != null:
			value_label.text = "%d / %d" % [_value_of(primary), _value_of(secondary)]
		else:
			value_label.text = "%d" % _value_of(primary)
		value_label.add_theme_font_size_override(&"font_size", 15)
		value_label.add_theme_color_override(&"font_color", color)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(value_label)


func _value_of(key: Variant) -> int:
	return int(observed_stats.values.get(key, 0))
