extends Control
## HUD mana bar — sibling of HealthBar (same stat-sync pattern). Smoothly tweens its
## fill on MANA / MANA_MAX change. No damage chip: spending mana isn't "damage", so a
## lagging red chunk would read wrong here. Mana gates special abilities only.

const FILL_TIME: float = 0.18

@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar

var _tween: Tween


func _ready() -> void:
	ClientState.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			local_player.stats_component.stats.stat_changed.connect(_on_stat_changed)
			_on_stat_changed(Stat.MANA_MAX, local_player.stats_component.get_stat(Stat.MANA_MAX))
			_on_stat_changed(Stat.MANA, local_player.stats_component.get_stat(Stat.MANA))
	)


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.MANA:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(progress_bar, ^"value", value, FILL_TIME)
		_update_label(value)
	elif stat_name == Stat.MANA_MAX:
		progress_bar.max_value = value
		_update_label(progress_bar.value)


func _update_label(value: float) -> void:
	label.text = "%d / %d" % [value, progress_bar.max_value]
