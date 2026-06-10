extends Control
## HUD mana bar — sibling of HealthBar (same pattern): subscribes to the local
## player's stat sync and mirrors MANA / MANA_MAX. Mana gates special abilities
## only, so this is the "how often can I use my power moves" gauge.


@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar


func _ready() -> void:
	ClientState.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			local_player.stats_component.stats.stat_changed.connect(_on_stat_changed)
			_on_stat_changed(Stat.MANA, local_player.stats_component.get_stat(Stat.MANA))
			_on_stat_changed(Stat.MANA_MAX, local_player.stats_component.get_stat(Stat.MANA_MAX))
	)


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.MANA:
		progress_bar.value = value
		_update_label()
	if stat_name == Stat.MANA_MAX:
		progress_bar.max_value = value
		_update_label()


func _update_label() -> void:
	label.text = "%d / %d" % [progress_bar.value, progress_bar.max_value]
