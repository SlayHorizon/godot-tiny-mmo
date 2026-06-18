extends CanvasLayer
## Lightweight transient toasts (client only). Call from anywhere:
##   Toaster.toast("Saved!")
##   Toaster.toast("Mining — Level 2!", 3.0)
## Toasts stack at the top-center of the screen and each fades out then frees itself.
## Purely cosmetic feedback — never gameplay-authoritative.

## How many toasts can be on screen at once (oldest is dropped past this).
const MAX_TOASTS: int = 5

## A repeat of the same coalesce key within this window merges into the existing
## card (bumps a ×N counter + pulses it) instead of spawning a new one. After this
## much silence the next event opens a fresh card.
const COALESCE_WINDOW_MS: int = 6000

## Sentinel for toast()'s optional font color — alpha 0 means "leave the theme
## default", any opaque color tints the label.
const NO_TINT: Color = Color(0, 0, 0, 0)

var _container: VBoxContainer

## Active coalescable toasts, keyed by a content-stable string (e.g. "kill:goblin",
## "mine:Iron Ore"). { key: { "panel", "vbox", "count": int, "last_ms": int } }.
## Cleared when the card frees (tree_exited).
var _active: Dictionary = {}


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


func toast(text: String, duration: float = 2.0, font_color: Color = NO_TINT) -> void:
	if _container == null:
		return

	# Drop the oldest toast(s) if we're at the cap.
	while _container.get_child_count() >= MAX_TOASTS:
		var oldest: Node = _container.get_child(0)
		_container.remove_child(oldest)
		oldest.queue_free()

	var panel: PanelContainer = _make_toast(text, font_color)
	_container.add_child(panel)
	_restart_dwell(panel, duration)


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
	_restart_dwell(panel, duration)


## Coalescing card for high-frequency events (kills, gather yields, quest
## progress). A repeat of [param key] within COALESCE_WINDOW_MS updates the SAME
## card — refreshes its lines, bumps a ×N counter into the title, and pulses it —
## instead of stacking another card. Empty key = no coalescing (falls back to a
## normal grouped card). This is what stops a pack of mobs / a vein of ore from
## flooding the screen.
func toast_feed(key: String, title: String, lines: PackedStringArray, duration: float = 2.0) -> void:
	if _container == null:
		return
	if key.is_empty():
		toast_group(title, lines, duration)
		return

	var now: int = Time.get_ticks_msec()
	if _active.has(key):
		var entry: Dictionary = _active[key]
		var existing: PanelContainer = entry.get("panel")
		if is_instance_valid(existing) and now - int(entry.get("last_ms", 0)) <= COALESCE_WINDOW_MS:
			entry["count"] = int(entry.get("count", 1)) + 1
			entry["last_ms"] = now
			_render_feed(entry["vbox"], title, lines, int(entry["count"]))
			_pulse(existing)
			_restart_dwell(existing, duration)
			return
		_active.erase(key) # stale / freed — open a fresh card

	while _container.get_child_count() >= MAX_TOASTS:
		var oldest: Node = _container.get_child(0)
		_container.remove_child(oldest)
		oldest.queue_free()

	var panel: PanelContainer = _make_panel_shell()
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override(&"separation", 2)
	(panel.get_child(0) as MarginContainer).add_child(vbox)
	_render_feed(vbox, title, lines, 1)
	# Drop our registry entry when this card frees, so the next event opens fresh.
	panel.tree_exited.connect(func() -> void:
		if (_active.get(key, {}) as Dictionary).get("panel") == panel:
			_active.erase(key))
	_container.add_child(panel)
	_active[key] = {"panel": panel, "vbox": vbox, "count": 1, "last_ms": now}
	_restart_dwell(panel, duration)


## (Re)render a feed card's content into its vbox: a title carrying the ×N count
## (hidden at 1) plus the event's lines. Reused on create and on every repeat —
## the panel node stays the same so its dwell + pulse tweens survive.
func _render_feed(vbox: VBoxContainer, title: String, lines: PackedStringArray, count: int) -> void:
	for child: Node in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()

	var title_label: Label = Label.new()
	title_label.text = title + (" ×%d" % count if count > 1 else "")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override(&"font_size", 15)
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


## A short scale bump — the "it happened again" feedback on a coalesced card.
## Independent of the fade/dwell tween (touches scale only, never modulate:a).
func _pulse(panel: Control) -> void:
	panel.pivot_offset = panel.size / 2.0
	var tween: Tween = create_tween()
	tween.tween_property(panel, ^"scale", Vector2(1.08, 1.08), 0.09)
	tween.tween_property(panel, ^"scale", Vector2.ONE, 0.09)


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


func _make_toast(text: String, font_color: Color = NO_TINT) -> PanelContainer:
	var panel: PanelContainer = _make_panel_shell()
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_color.a > 0.0:
		label.add_theme_color_override(&"font_color", font_color)
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
