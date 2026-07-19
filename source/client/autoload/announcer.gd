extends CanvasLayer
## Center-screen event banners (client only) — the "big moment" lane, distinct from
## Toaster's corner cards. Call from anywhere:
##   Announcer.announce("Level 7", "+2 attribute points")
##   Announcer.announce("Goblin Woodland", "Levels 1-5", {"delay": 1.0})
## Banners queue (never overlap) and each fades in big over the upper third of the
## screen, dwells, then fades out. Purely cosmetic feedback — never gameplay-
## authoritative. Options: "color" (title tint), "duration" (dwell seconds),
## "delay" (seconds before showing — lets a warp fade finish first), "sound" (bool).

const TITLE_COLOR: Color = Color(1.0, 0.95, 0.8)
const SUBTITLE_COLOR: Color = Color(0.85, 0.86, 0.92)
const OUTLINE_COLOR: Color = Color(0.05, 0.06, 0.1, 0.85)

## Pending banners: {"title", "subtitle", "color", "duration", "delay", "sound"}.
var _queue: Array[Dictionary] = []
var _busy: bool = false


func _ready() -> void:
	# Mirrors Toaster: this is client-only UI.
	if not GameMode.is_client():
		queue_free()
		return
	layer = 100 # Above the world + HUD; below Toaster (128).


func announce(title: String, subtitle: String = "", opts: Dictionary = {}) -> void:
	if not GameMode.is_client() or title.is_empty():
		return
	_queue.append({
		"title": title,
		"subtitle": subtitle,
		"color": opts.get("color", TITLE_COLOR),
		"duration": float(opts.get("duration", 3.0)),
		"delay": float(opts.get("delay", 0.0)),
		"sound": bool(opts.get("sound", true)),
	})
	if not _busy:
		_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var entry: Dictionary = _queue.pop_front()

	var delay: float = float(entry["delay"])
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	# High on the screen, well clear of the player character (top-down = the
	# action lives at center; the banner must not sit on it).
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 70.0
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override(&"separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	add_child(box)

	var title_color: Color = entry["color"]
	var title_label: Label = _make_label(str(entry["title"]), 34, title_color)
	box.add_child(title_label)

	# The zone-text flourish: a thin rule under the title that sweeps outward
	# from the center as the text fades in (the Genshin/WoW treatment — motion
	# is what makes the reveal read, not the text popping into place).
	var rule_center: CenterContainer = CenterContainer.new()
	rule_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(title_color.r, title_color.g, title_color.b, 0.75)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_center.add_child(rule)
	box.add_child(rule_center)

	var subtitle_text: String = str(entry["subtitle"])
	if not subtitle_text.is_empty():
		box.add_child(_make_label(subtitle_text, 15, SUBTITLE_COLOR))

	if bool(entry["sound"]):
		# Full volume + a slightly lower pitch than button reveals — reads
		# "event", not "click", without needing a new asset (jingle = open ask).
		UISound.play(UISound.REVEAL, 0.85, 0.0)

	# Slow fade-in with a settle-down drift + the rule sweep, dwell, slow fade
	# out — then the next queued banner (if any) takes the stage.
	var start_top: float = box.offset_top
	box.offset_top = start_top - 18.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(box, ^"modulate:a", 1.0, 0.6)
	tween.tween_property(box, ^"offset_top", start_top, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(rule, ^"custom_minimum_size:x", 260.0, 0.65)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(false)
	tween.tween_interval(float(entry["duration"]))
	tween.tween_property(box, ^"modulate:a", 0.0, 0.9)
	tween.tween_callback(box.queue_free)
	tween.tween_callback(_play_next)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	# Dark outline so the text reads over any biome, bright or dark.
	label.add_theme_color_override(&"font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override(&"outline_size", 6)
	return label
