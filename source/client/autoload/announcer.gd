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

## Pending banners: {"title", "subtitle", "eyebrow", "color", "duration",
## "delay", "sound", "key"}.
var _queue: Array[Dictionary] = []
var _busy: bool = false
## Generation counter: bumped when the active banner is cancelled/replaced, so a
## play coroutine parked on its delay timer knows to abort.
var _play_id: int = 0
## The banner currently on screen: {key, title, subtitle, box, tween}.
var _current: Dictionary = {}


func _ready() -> void:
	# Mirrors Toaster: this is client-only UI.
	if not GameMode.is_client():
		queue_free()
		return
	layer = 110 # Above the world, HUD AND WarpFade (100) — a portal warning's tail
	# stays readable as a fade starts, and zone text over the dark warp screen reads
	# cinematic rather than swallowed. Toaster (128) stays on top.


func announce(title: String, subtitle: String = "", opts: Dictionary = {}) -> void:
	if not GameMode.is_client() or title.is_empty():
		return
	var key: String = str(opts.get("key", ""))
	var entry: Dictionary = {
		"title": title,
		"subtitle": subtitle,
		"eyebrow": str(opts.get("eyebrow", "")),
		"color": opts.get("color", TITLE_COLOR),
		"duration": float(opts.get("duration", 3.0)),
		"delay": float(opts.get("delay", 0.0)),
		"sound": bool(opts.get("sound", true)),
		"sfx": str(opts.get("sfx", "")), # per-cue sound path; "" = generic reveal
		"sfx_pitch": float(opts.get("sfx_pitch", 1.0)),
		"sfx_db": float(opts.get("sfx_db", 0.0)),
		"key": key,
	}
	if key.is_empty():
		# Ceremonies OUTRANK positional hints: a level-up / wardstone /
		# discovery takes the stage instantly over a "way is sealed" hint — by
		# the time a ceremony fires, the hint's context is already history.
		# Ceremony-vs-ceremony still queues (each deserves its full moment).
		var cur_key: String = str(_current.get("key", ""))
		if _busy and not cur_key.is_empty():
			_cancel_current()
			_queue.push_front(entry)
			_play_next()
			return
	if not key.is_empty():
		# Keyed banners are POSITIONAL hints (sealed portal, level warning) —
		# only the newest matters. Drop queued siblings so sprinting along a row
		# of portals can never build a backlog...
		var kept: Array[Dictionary] = []
		for queued: Dictionary in _queue:
			if str(queued["key"]) != key:
				kept.append(queued)
		_queue = kept
		# ...and REPLACE a same-key banner already on screen instead of queueing
		# behind it. Same text still showing (re-entered the same portal) = just
		# extend its dwell, no re-fade blink.
		var cur_box: Control = _current.get("box")
		if _busy and str(_current.get("key", "")) == key \
				and cur_box != null and is_instance_valid(cur_box):
			if str(_current.get("title", "")) == title and str(_current.get("subtitle", "")) == subtitle:
				_extend_dwell(float(entry["duration"]))
				return
			_cancel_current()
			_queue.push_front(entry)
			_play_next()
			return
	_queue.append(entry)
	if not _busy:
		_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		_busy = false
		_current = {}
		return
	_busy = true
	_play_id += 1
	var id: int = _play_id
	var entry: Dictionary = _queue.pop_front()
	_current = {} # nothing on screen during the delay — don't match stale keys

	var delay: float = float(entry["delay"])
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if id != _play_id:
			return # cancelled/replaced while waiting out the delay

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
	# Optional eyebrow — the small tag line ABOVE the title ("New region
	# discovered", "Warning"). Same color family as the title so a red warning
	# reads red top to bottom.
	var eyebrow_text: String = str(entry["eyebrow"])
	if not eyebrow_text.is_empty():
		box.add_child(_make_label(eyebrow_text, 13, title_color))
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
		var sfx: String = str(entry["sfx"])
		if not sfx.is_empty():
			UISound.play(sfx, float(entry["sfx_pitch"]), float(entry["sfx_db"]))
		else:
			# Generic banner reveal: full volume, slightly lower pitch than
			# button reveals — reads "event", not "click".
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
	_current = {
		"key": str(entry["key"]),
		"title": str(entry["title"]),
		"subtitle": str(entry["subtitle"]),
		"box": box,
		"tween": tween,
	}


## Retire positional (keyed) banners, queued AND on-screen. Their context is a
## PLACE — call on map change (a "sealed portal" hint must never follow the
## player into the next biome) and on stepping out of a portal. SOFT by design
## (owner call 2026-07-20): the on-screen banner gets its normal graceful
## fade-out immediately instead of vanishing — the player keeps a beat to
## finish reading. Hard cancels stay reserved for actual replacement
## (same-key swap, ceremony preemption). Ceremonies (unkeyed) are untouched.
func dismiss_positional() -> void:
	var kept: Array[Dictionary] = []
	for queued: Dictionary in _queue:
		if str(queued["key"]).is_empty():
			kept.append(queued)
	_queue = kept
	if _busy and not str(_current.get("key", "")).is_empty():
		_extend_dwell(0.0) # zero remaining dwell = fade out now, gracefully


## Tear down the on-screen banner immediately — the keyed-replacement path.
func _cancel_current() -> void:
	_play_id += 1 # aborts any play coroutine parked on its delay timer
	var tween: Tween = _current.get("tween")
	if tween != null and tween.is_valid():
		tween.kill()
	var box: Node = _current.get("box")
	if box != null and is_instance_valid(box):
		box.queue_free()
	_current = {}
	_busy = false


## Same keyed banner re-announced with identical text (re-entered the same
## portal): keep it on screen and restart its dwell + fade-out instead of
## re-playing the whole entrance.
func _extend_dwell(duration: float) -> void:
	var box: Control = _current.get("box")
	if box == null or not is_instance_valid(box):
		return
	var old: Tween = _current.get("tween")
	if old != null and old.is_valid():
		old.kill()
	box.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(duration)
	tween.tween_property(box, ^"modulate:a", 0.0, 0.9)
	tween.tween_callback(box.queue_free)
	tween.tween_callback(_play_next)
	_current["tween"] = tween


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
