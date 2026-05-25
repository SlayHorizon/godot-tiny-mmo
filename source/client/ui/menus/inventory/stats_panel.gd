extends PanelContainer


var observed_stats: StatsComponent.Stats

@export var stats_display: RichTextLabel


func _ready() -> void:
	_try_watch()
	# Re-watch if the local player wasn't ready yet when this panel loaded.
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _try_watch())


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
	if not observed_stats:
		return

	stats_display.clear()
	stats_display.text = ""

	stats_display.push_table(2)
	stats_display.set_table_column_expand(0, true)
	stats_display.set_table_column_expand(1, true, 10)

	add_stat_text("HP %d/%d", Color("#3de600"),
		[observed_stats.values.get(Stat.HEALTH, 0), observed_stats.values.get(Stat.HEALTH_MAX, 0)]
	)
	
	add_stat_text("Mana %d", Color("#009dc4"),
		[observed_stats.values.get(Stat.MANA_MAX, 0)]
	)
	
	add_stat_text("Attack %d", Color("#fc7f03"),
		[observed_stats.values.get(Stat.AD, 0)]
	)
	
	add_stat_text("Armor %d", Color("#fc7f03"),
		[observed_stats.values.get(Stat.ARMOR, 0)]
	)
	
	add_stat_text("Magic %d", Color("#6f03fc"),
		[observed_stats.values.get(Stat.AP, 0)]
	)
	
	add_stat_text("MagicRes %d", Color("#6f03fc"),
		[observed_stats.values.get(Stat.MR, 0)]
	)

	add_stat_text("Move Speed %d", Color("#dbd802"),
		[observed_stats.values.get(Stat.MOVE_SPEED, 0)]
	)
	
	add_stat_text("Tenacity %d", Color("#619902"),
		[observed_stats.values.get(&"tenacity", 0)]
	)
	
	stats_display.pop()


func add_stat_text(text: String, color: Color, _stats: Array) -> void:
	stats_display.push_cell()
	stats_display.push_color(color)
	stats_display.append_text(text % _stats)
	stats_display.pop()
	stats_display.pop()


func _on_details_button_pressed() -> void:
	# Bad practice but good for fast test
	$"../EquipmentSlots".visible = not $"../EquipmentSlots".visible
	$"../HBoxContainer".visible = not $"../HBoxContainer".visible
