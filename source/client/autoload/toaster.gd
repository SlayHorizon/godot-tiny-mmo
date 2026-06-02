extends CanvasLayer
## Lightweight transient toasts (client only). Call from anywhere:
##   Toaster.toast("Saved!")
##   Toaster.toast("Mining — Level 2!", 3.0)
## Toasts stack at the top-center of the screen and each fades out then frees itself.
## Purely cosmetic feedback — never gameplay-authoritative.

## How many toasts can be on screen at once (oldest is dropped past this).
const MAX_TOASTS: int = 5

## Extra dwell time (seconds) granted per additional toast on screen, so
## bursts (e.g. a quest turn-in: title + XP + gold + level-up at once) stay
## readable instead of flashing past in one shared 2s window.
const EXTRA_DWELL_PER_STACKED: float = 0.8

var _container: VBoxContainer


func _ready() -> void:
	# Mirrors ClientState/Client: this is client-only UI.
	if not GameMode.is_client():
		queue_free()
		return

	layer = 128 # Above the HUD and menus.
	_container = VBoxContainer.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_container.offset_top = 32.0
	_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	_container.add_theme_constant_override(&"separation", 6)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)


func toast(text: String, duration: float = 2.0) -> void:
	if _container == null:
		return

	# Drop the oldest toast(s) if we're at the cap.
	while _container.get_child_count() >= MAX_TOASTS:
		var oldest: Node = _container.get_child(0)
		_container.remove_child(oldest)
		oldest.queue_free()

	var panel: PanelContainer = _make_toast(text)
	_container.add_child(panel)
	_kick_dwell(duration)


## Show a multi-line card: bold-ish title + a list of sub-lines. Use when
## one logical event produces several feedback strings (kill = "Defeated
## a Goblin" + "+15 XP" + "Looted 1 Tooth"; quest turn-in = title + XP +
## gold + level-up). Renders as ONE PanelContainer so the player reads it
## as one notification instead of a flood of 3-4 separate toasts.
func toast_group(title: String, lines: PackedStringArray, duration: float = 2.0) -> void:
	if _container == null:
		return
	if title.is_empty() and lines.is_empty():
		return

	while _container.get_child_count() >= MAX_TOASTS:
		var oldest: Node = _container.get_child(0)
		_container.remove_child(oldest)
		oldest.queue_free()

	var panel: PanelContainer = _make_group_toast(title, lines)
	_container.add_child(panel)
	_kick_dwell(duration)


## Scale dwell with the stack so a burst stays readable, then reset every
## visible toast's tween to this new dwell — older ones get extended too.
func _kick_dwell(base_duration: float) -> void:
	var stack_size: int = _container.get_child_count()
	var dwell: float = base_duration + maxf(0.0, (stack_size - 1) * EXTRA_DWELL_PER_STACKED)
	for sibling: Node in _container.get_children():
		_restart_dwell(sibling as Control, dwell)

## Cancel any in-flight tween on this panel and start a fresh fade-in / dwell /
## fade-out sequence. Idempotent — calling repeatedly just keeps shifting the
## dismissal forward, which is exactly the "burst keeps the stack alive" behaviour.
func _restart_dwell(panel: Control, dwell: float) -> void:
	if panel == null:
		return
	if panel.has_meta(&"tween"):
		var old: Tween = panel.get_meta(&"tween")
		if old and old.is_valid():
			old.kill()
	var tween: Tween = create_tween()
	tween.tween_property(panel, ^"modulate:a", 1.0, 0.15)
	tween.tween_interval(dwell)
	tween.tween_property(panel, ^"modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)
	panel.set_meta(&"tween", tween)


func _make_toast(text: String) -> PanelContainer:
	var panel: PanelContainer = _make_panel_shell()
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(panel.get_child(0) as MarginContainer).add_child(label)
	return panel


func _make_group_toast(title: String, lines: PackedStringArray) -> PanelContainer:
	var panel: PanelContainer = _make_panel_shell()
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override(&"separation", 2)
	(panel.get_child(0) as MarginContainer).add_child(vbox)

	if not title.is_empty():
		var title_label: Label = Label.new()
		title_label.text = title
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_size_override(&"font_size", 16)
		title_label.add_theme_color_override(&"font_color", Color(1, 0.95, 0.75, 1))
		vbox.add_child(title_label)

	for line: String in lines:
		if line.is_empty():
			continue
		var sub: Label = Label.new()
		sub.text = line
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_color_override(&"font_color", Color(0.88, 0.88, 0.9, 1))
		vbox.add_child(sub)

	return panel


## Shared panel + margin scaffolding used by both single-line and grouped
## toasts. The single child of the panel is always the MarginContainer the
## caller can append text widgets into.
func _make_panel_shell() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.modulate.a = 0.0

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override(&"panel", style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 14)
	margin.add_theme_constant_override(&"margin_right", 14)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	panel.add_child(margin)

	return panel
