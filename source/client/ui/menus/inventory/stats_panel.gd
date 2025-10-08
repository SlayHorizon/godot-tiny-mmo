extends PanelContainer


var stats: Dictionary

@onready var stats_display: RichTextLabel = $VBoxContainer/RichTextLabel


func _ready() -> void:
	InstanceClient.subscribe(&"stats.update", fill_stats)
	# If already stored.
	fill_stats(ClientState.stats.data)


func fill_stats(data: Dictionary) -> void:
	if data.is_empty():
		return
	ClientState.stats.data.merge(data, true)
	
	stats_display.text = ""
	
	stats = ClientState.stats.data.duplicate()
	
	stats_display.push_table(2)
	stats_display.set_table_column_expand(0, true)
	stats_display.set_table_column_expand(1, true)
	
	
	add_stat_text("HP %d/%d", Color("#3de600"),
		[stats.get(StatsCatalog.HEALTH, 0), stats.get(StatsCatalog.HEALTH, 0)]
	)
	
	add_stat_text("Mana %d", Color("#009dc4"),
		[stats.get(StatsCatalog.MANA, 0)]
	)
	
	add_stat_text("Attack %d", Color("#fc7f03"),
		[stats.get(StatsCatalog.AD, 0)]
	)
	
	add_stat_text("Armor %d", Color("#fc7f03"),
		[stats.get(StatsCatalog.ARMOR, 0)]
	)
	
	add_stat_text("Magic %d", Color("#6f03fc"),
		[stats.get(StatsCatalog.AP, 0)]
	)
	
	add_stat_text("MagicRes %d", Color("#6f03fc"),
		[stats.get(StatsCatalog.MR, 0)]
	)

	add_stat_text("Speed %d", Color("#dbd802"),
		[stats.get(StatsCatalog.MOVE_SPEED, 0)]
	)
	
	add_stat_text("Tenacity %d", Color("#619902"),
		[stats.get(&"tenacity", 0)]
	)
	
	stats_display.pop()


func add_stat_text(text: String, color: Color, stats: Array) -> void:
	stats_display.push_cell()
	stats_display.push_color(color)
	stats_display.append_text(text % stats)
	stats_display.pop()
	stats_display.pop()


func _on_details_button_pressed() -> void:
	# Bad practice but good for fast test
	$"../EquipmentSlots".visible = not $"../EquipmentSlots".visible
	$"../HBoxContainer".visible = not $"../HBoxContainer".visible
