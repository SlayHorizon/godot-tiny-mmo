class_name DungeonHud
extends PanelContainer
## Top-center dungeon-run HUD: a live MM:SS run clock and — on HARD runs — the shared revive count.
## Driven entirely by &"dungeon.hud" pushes from DungeonService: {active, elapsed_s, has_pool,
## revives}. The clock ticks LOCALLY (the server sends the elapsed baseline on entry and re-syncs it
## on each revive change), so there's no per-second network spam. Hidden whenever no run is active.

var _has_pool: bool = false
var _revives: int = 0
## Local clock baseline: the run-elapsed (seconds) captured at the last push + the ticks_msec then.
var _base_elapsed_s: float = 0.0
var _base_tick_ms: int = 0
var _last_shown_sec: int = -1

var _timer_label: Label
var _revive_label: Label


func _ready() -> void:
	_build_ui()
	visible = false
	set_process(false)
	Client.subscribe(&"dungeon.hud", _on_dungeon_hud)


## {active:false} ends the display; {active:true, elapsed_s, has_pool, revives} shows / updates it.
func _on_dungeon_hud(payload: Dictionary) -> void:
	if not bool(payload.get("active", false)):
		visible = false
		set_process(false)
		return
	# Re-base the local clock whenever the server sends an elapsed (entry + every revive change).
	if payload.has("elapsed_s"):
		_base_elapsed_s = float(payload["elapsed_s"])
		_base_tick_ms = Time.get_ticks_msec()
	_has_pool = bool(payload.get("has_pool", false))
	_revives = int(payload.get("revives", 0))
	_refresh_revives()
	_last_shown_sec = -1 # force an immediate clock redraw
	_update_clock()
	visible = true
	set_process(true)


func _process(_delta: float) -> void:
	_update_clock()


## Tick the MM:SS clock from the local baseline, throttled to one redraw per whole second.
func _update_clock() -> void:
	var elapsed: float = _base_elapsed_s + float(Time.get_ticks_msec() - _base_tick_ms) / 1000.0
	var total: int = maxi(0, int(elapsed))
	if total == _last_shown_sec:
		return
	_last_shown_sec = total
	# float division + floori for the minutes — avoids the int/int "integer division" warning.
	_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]


## Show "Revives: N" only on HARD runs; redden it at 0 (one more death wipes the run).
func _refresh_revives() -> void:
	_revive_label.visible = _has_pool
	if not _has_pool:
		return
	_revive_label.text = "Revives: %d" % _revives
	_revive_label.add_theme_color_override(
		&"font_color", Color(1.0, 0.3, 0.3) if _revives <= 0 else Color(1.0, 0.62, 0.62))


## Compact dark panel, top-center just below the status-effect strip. Built in code (mirrors the
## lazily-built SparringCountdown) so hud.tscn's unique_id node table is left untouched.
func _build_ui() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = 44.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.06, 0.08, 0.55)
	panel.set_corner_radius_all(10)
	panel.content_margin_top = 5
	panel.content_margin_bottom = 5
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	add_theme_stylebox_override(&"panel", panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override(&"font_size", 26)
	_timer_label.text = "00:00"
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_timer_label)

	_revive_label = Label.new()
	_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_label.add_theme_font_size_override(&"font_size", 14)
	_revive_label.text = "Revives: 0"
	_revive_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_revive_label)
