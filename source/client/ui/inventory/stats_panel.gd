extends PanelContainer


var stats: Dictionary

# Is there a better way ?
@onready var stats_column1: RichTextLabel = $VBoxContainer/HBoxContainer2/RichTextLabel
@onready var stats_column2: RichTextLabel = $VBoxContainer/HBoxContainer2/RichTextLabel2


func _ready() -> void:
	InstanceClient.subscribe(&"stats.get", fill_stats)
	InstanceClient.subscribe(&"stats.update", update_stats)
	if Events.cache_data.has("stats"):
		fill_stats(Events.cache_data["stats"])


func fill_stats(data: Dictionary) -> void:
	#if data.is_empty():
	if not Events.cache_data.has("stats"):
		Events.cache_data["stats"] = data
	#if stats.is_empty():
	stats_column1.text = ""
	stats_column2.text = ""
	
	stats = data
	
	stats_column1.push_table(2)
	stats_column1.set_table_column_expand(0, true)
	stats_column1.set_table_column_expand(1, true)
	
	for stat_name: StringName in data:
		stats_column1.push_cell()
		match stat_name:
			StatsCatalog.HEALTH:
				stats_column1.append_text("[color=#08b502]HP %d[/color]" % data[stat_name])
			StatsCatalog.MANA:
				#stats_column2.append_text("[color=#009dc4]Mana %d[/color]" % data[stat_name])
				stats_column1.append_text("[color=#009dc4]Mana %d[/color]" % data[stat_name])
			_:
				stats_column1.append_text("%s %d" % [stat_name, data[stat_name]])
		stats_column1.pop()
	stats_column1.pop()


func update_stats(stats_to_update: Dictionary) -> void:
	fill_stats(Events.cache_data[&"stats"])
