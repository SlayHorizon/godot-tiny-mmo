extends Control
## HUD health bar with a "damage chip": the green MainBar tweens to current HP while a
## red ChipBar behind it LAGS on damage, leaving a red chunk that lingers a beat then
## drains — so a hit reads instantly. Heals / init move both together, so no red shows.
## The red is the ChipBar's fill; the dark empty track is the ChipBar's themed (XPBar)
## background, showing through MainBar's transparent background.

const FILL_TIME: float = 0.18
const CHIP_DELAY: float = 0.35
const CHIP_DRAIN: float = 0.45
const LOW_HP_RATIO: float = 0.25
const LOW_PULSE_TIME: float = 0.5
const LOW_PULSE_BRIGHT: Color = Color(1.7, 1.7, 1.7)

@onready var chip_bar: ProgressBar = $ChipBar
@onready var main_bar: ProgressBar = $MainBar
@onready var label: Label = $MainBar/Label

var _main_tween: Tween
var _chip_tween: Tween
var _low: bool = false
var _pulse_tween: Tween


func _ready() -> void:
	ClientState.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			local_player.stats_component.stats.stat_changed.connect(_on_stat_changed)
			_on_stat_changed(Stat.HEALTH_MAX, local_player.stats_component.get_stat(Stat.HEALTH_MAX))
			_on_stat_changed(Stat.HEALTH, local_player.stats_component.get_stat(Stat.HEALTH))
	)


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.HEALTH:
		_set_health(value)
	elif stat_name == Stat.HEALTH_MAX:
		chip_bar.max_value = value
		main_bar.max_value = value
		_update_label(main_bar.value)


## Drive both bars: MainBar (green) always tweens to the new value; ChipBar (red) lags
## behind on damage to leave the red chunk, but rides along on heals so none shows.
func _set_health(new_health: float) -> void:
	var old: float = main_bar.value
	if _main_tween != null and _main_tween.is_valid():
		_main_tween.kill()
	_main_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_main_tween.tween_property(main_bar, ^"value", new_health, FILL_TIME)

	if _chip_tween != null and _chip_tween.is_valid():
		_chip_tween.kill()
	if new_health < old:
		# Damage — hold the red chunk a beat, then drain it down to the new value.
		_chip_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_chip_tween.tween_interval(CHIP_DELAY)
		_chip_tween.tween_property(chip_bar, ^"value", new_health, CHIP_DRAIN)
	else:
		# Heal / init — the chip rides with the fill so no red shows.
		_chip_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_chip_tween.tween_property(chip_bar, ^"value", new_health, FILL_TIME)

	var ratio: float = new_health / main_bar.max_value if main_bar.max_value > 0.0 else 1.0
	_set_low(ratio <= LOW_HP_RATIO and new_health > 0.0)
	_update_label(new_health)


func _update_label(value: float) -> void:
	label.text = "%d / %d" % [value, main_bar.max_value]


## Below LOW_HP_RATIO the green fill throbs brighter as a danger cue. Uses self_modulate
## (the node's own draw only) so the child readout label stays steady. Cleared on recovery.
func _set_low(low: bool) -> void:
	if low == _low:
		return
	_low = low
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if low:
		_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(main_bar, ^"self_modulate", LOW_PULSE_BRIGHT, LOW_PULSE_TIME)
		_pulse_tween.tween_property(main_bar, ^"self_modulate", Color.WHITE, LOW_PULSE_TIME)
	else:
		main_bar.self_modulate = Color.WHITE
