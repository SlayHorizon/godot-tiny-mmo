extends MenuShell
## Daily quest board. Themed cards (type icon + objective + progress bar + reward
## chips + a per-state claim button), a completion-bonus track, and a reset
## countdown. Built on MenuShell so it gets the shared dim modal backdrop (no more
## click-through to the HUD) + themed card + Close chrome for free. Auto-fetches
## on open and updates live from the server's daily.progress push.

const COLOR_GOLD: Color = Color(1.0, 0.92, 0.72)
const COLOR_ACCENT: Color = Color(0.96, 0.74, 0.16)
const COLOR_GREEN: Color = Color(0.52, 0.79, 0.42)
const COLOR_MUTED: Color = Color(0.7, 0.72, 0.78)
const COLOR_CARD: Color = Color(0.11, 0.13, 0.18)
const COLOR_TILE: Color = Color(0.06, 0.075, 0.11)
const COLOR_TRACK: Color = Color(0.04, 0.05, 0.08)
const COLOR_ICON: Color = Color(0.9, 0.85, 0.7)
const COLOR_XP: Color = Color(0.62, 0.79, 1.0)   # experience — cool blue
const COLOR_COIN: Color = Color(1.0, 0.82, 0.42) # gold currency — amber

## Indexed by DailyQuestTemplate.Kind (KILL, COLLECT, SPAR, DUNGEON, CRAFT).
const KIND_ICON_NAMES: PackedStringArray = ["kill", "collect", "spar", "dungeon", "craft"]

var _reset_pill: Label
var _entries_box: VBoxContainer


func _ready() -> void:
	build_shell("Daily quests", null, true)
	visibility_changed.connect(_on_visibility_changed)

	# Reset countdown sits in the header's centre slot as a pill.
	_reset_pill = Label.new()
	_reset_pill.add_theme_stylebox_override(&"normal", _flat(COLOR_TILE, 999, Color(1, 1, 1, 0.08), 1))
	_reset_pill.add_theme_color_override(&"font_color", COLOR_MUTED)
	_reset_pill.add_theme_font_size_override(&"font_size", 12)
	header_center.add_child(_reset_pill)

	# Body: a scrolling column so a longer set never overflows the card.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_entries_box)

	# Live progress: the server pushes the full board whenever a daily counter
	# advances, so an open board updates without reopening.
	Client.subscribe(&"daily.progress", _on_progress)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


## Live board push (daily.progress) — only reflow if the board is on screen.
func _on_progress(payload: Dictionary) -> void:
	if visible:
		_apply(payload)


## Called by HUD.display_menu when opened with an arg (unused — one set per player).
func open(_unused: int) -> void:
	_refresh()


func _refresh() -> void:
	_message("Loading...")
	Client.request_data(
		&"quest.board.info",
		_apply,
		{},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _apply(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		_message("Couldn't load dailies: %s" % response.get("reason", "unknown"))
		return
	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		_message("No dailies available at your level yet.")
		return

	for child: Node in _entries_box.get_children():
		child.queue_free()

	var refresh_at_ms: int = int(response.get("refresh_at_ms", 0))
	var seconds_left: int = maxi(0, int((refresh_at_ms - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	_reset_pill.text = "  Resets in %s  " % _fmt_duration(seconds_left)

	_entries_box.add_child(_build_bonus_track(response, entries))
	for entry: Dictionary in entries:
		_entries_box.add_child(_build_row(entry))


# ---------------------------------------------------------------------------
# Completion-bonus track
# ---------------------------------------------------------------------------

func _build_bonus_track(response: Dictionary, entries: Array) -> Control:
	var total: int = entries.size()
	var claimed: int = 0
	for e: Variant in entries:
		if bool((e as Dictionary).get("claimed", false)):
			claimed += 1
	var done: bool = bool(response.get("all_claimed", false))
	var bonus_xp: int = int(response.get("bonus_xp", 0))
	var bonus_gold: int = int(response.get("bonus_gold", 0))

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _flat(COLOR_TILE, 10, COLOR_ACCENT, 1 if done else 0))
	var row: HBoxContainer = _padded_row(panel, 10)
	row.add_theme_constant_override(&"separation", 12)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 6)
	row.add_child(col)

	var head: Label = Label.new()
	head.text = "Daily bonus earned" if done else "Complete all %d for a bonus" % total
	head.add_theme_color_override(&"font_color", COLOR_ACCENT if done else COLOR_GOLD)
	head.add_theme_font_size_override(&"font_size", 13)
	col.add_child(head)

	var seg: HBoxContainer = HBoxContainer.new()
	seg.add_theme_constant_override(&"separation", 5)
	col.add_child(seg)
	for i: int in total:
		var pip: PanelContainer = PanelContainer.new()
		pip.custom_minimum_size = Vector2(0, 5)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.add_theme_stylebox_override(&"panel", _flat(COLOR_ACCENT if i < claimed else COLOR_TRACK, 3))
		seg.add_child(pip)

	var reward: Label = Label.new()
	reward.text = "+%d XP  ·  %d g" % [bonus_xp, bonus_gold]
	reward.add_theme_color_override(&"font_color", COLOR_ACCENT if done else COLOR_MUTED)
	reward.add_theme_font_size_override(&"font_size", 13)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(reward)
	return panel


# ---------------------------------------------------------------------------
# Quest card
# ---------------------------------------------------------------------------

func _build_row(entry: Dictionary) -> Control:
	var complete: bool = bool(entry.get("complete", false))
	var claimed: bool = bool(entry.get("claimed", false))
	var progress: int = int(entry.get("progress", 0))
	var required: int = maxi(1, int(entry.get("required", 1)))

	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", _flat(COLOR_CARD, 12, COLOR_ACCENT if (complete and not claimed) else Color(1, 1, 1, 0.06), 1))
	var row: HBoxContainer = _padded_row(card, 14)
	row.add_theme_constant_override(&"separation", 14)

	var tile: PanelContainer = PanelContainer.new()
	tile.custom_minimum_size = Vector2(46, 46)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override(&"panel", _flat(COLOR_TILE, 10))
	var tile_pad: MarginContainer = MarginContainer.new()
	for s: String in ["left", "right", "top", "bottom"]:
		tile_pad.add_theme_constant_override("margin_" + s, 10)
	tile.add_child(tile_pad)
	var icon: TextureRect = TextureRect.new()
	icon.texture = _icon_for(int(entry.get("kind", 0)))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = COLOR_MUTED if claimed else COLOR_ICON
	tile_pad.add_child(icon)
	row.add_child(tile)

	var mid: VBoxContainer = VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override(&"separation", 7)
	row.add_child(mid)

	var desc: Label = Label.new()
	desc.text = str(entry.get("description", "?"))
	desc.add_theme_color_override(&"font_color", COLOR_MUTED if claimed else COLOR_GOLD)
	desc.add_theme_font_size_override(&"font_size", 15)
	mid.add_child(desc)

	var prow: HBoxContainer = HBoxContainer.new()
	prow.add_theme_constant_override(&"separation", 10)
	mid.add_child(prow)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = required
	bar.value = progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override(&"background", _flat(COLOR_TRACK, 4))
	bar.add_theme_stylebox_override(&"fill", _flat(COLOR_GREEN if complete else COLOR_ACCENT, 4))
	prow.add_child(bar)
	var count: Label = Label.new()
	count.text = "%d / %d" % [progress, required]
	count.add_theme_color_override(&"font_color", COLOR_GREEN if complete else COLOR_MUTED)
	count.add_theme_font_size_override(&"font_size", 12)
	prow.add_child(count)

	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override(&"separation", 6)
	mid.add_child(chips)
	chips.add_child(_chip("%d XP" % int(entry.get("reward_xp", 0)), COLOR_XP))
	chips.add_child(_chip("%d g" % int(entry.get("reward_gold", 0)), COLOR_COIN))

	# Right side: a claim action or a claimed marker — nothing while it's just in
	# progress (the bar already conveys that; no misleading "Locked").
	if claimed or complete:
		row.add_child(_build_claim(entry, claimed))
	return card


func _build_claim(entry: Dictionary, claimed: bool) -> Control:
	if claimed:
		var done: Label = Label.new()
		done.text = "Claimed ✓"
		done.add_theme_color_override(&"font_color", COLOR_GREEN)
		done.add_theme_font_size_override(&"font_size", 13)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return done
	# Reached only when the objective is complete (see _build_row): offer the claim.
	var claim: Button = Button.new()
	claim.text = "Claim"
	claim.custom_minimum_size = Vector2(84, 38)
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim.add_theme_stylebox_override(&"normal", _flat(COLOR_ACCENT, 8))
	claim.add_theme_stylebox_override(&"hover", _flat(COLOR_ACCENT.lightened(0.08), 8))
	claim.add_theme_stylebox_override(&"pressed", _flat(COLOR_ACCENT.darkened(0.1), 8))
	claim.add_theme_color_override(&"font_color", Color(0.15, 0.11, 0.03))
	claim.add_theme_color_override(&"font_hover_color", Color(0.15, 0.11, 0.03))
	claim.pressed.connect(_claim.bind(int(entry.get("template_id", 0))))
	return claim


func _claim(template_id: int) -> void:
	Client.request_data(
		&"quest.board.claim",
		_on_claimed,
		{"template_id": template_id},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_claimed(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		_message("Claim failed: %s" % response.get("reason", "unknown"))
		return
	_refresh()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Replace the board body with a single centered message (loading / error / empty).
func _message(text: String) -> void:
	for child: Node in _entries_box.get_children():
		child.queue_free()
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", COLOR_MUTED)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_entries_box.add_child(label)


## A card/panel + inner MarginContainer + HBox, returning the HBox for content.
func _padded_row(parent: PanelContainer, margin: int) -> HBoxContainer:
	var pad: MarginContainer = MarginContainer.new()
	for s: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, margin)
	parent.add_child(pad)
	var row: HBoxContainer = HBoxContainer.new()
	pad.add_child(row)
	return row


func _chip(text: String, text_color: Color) -> Control:
	var lbl: Label = Label.new()
	lbl.text = " " + text + " "
	lbl.add_theme_stylebox_override(&"normal", _flat(COLOR_TILE, 999))
	lbl.add_theme_color_override(&"font_color", text_color)
	lbl.add_theme_font_size_override(&"font_size", 12)
	return lbl


## A flat rounded StyleBox. [param border_w] 0 = no border.
func _flat(bg: Color, radius: int, border_col: Color = Color.BLACK, border_w: int = 0) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	return sb


func _icon_for(kind: int) -> Texture2D:
	if kind < 0 or kind >= KIND_ICON_NAMES.size():
		return null
	return load("res://assets/sprites/ui/daily/%s.png" % KIND_ICON_NAMES[kind]) as Texture2D


func _fmt_duration(seconds: int) -> String:
	if seconds <= 0:
		return "now"
	@warning_ignore("integer_division")
	var h: int = seconds / 3600
	@warning_ignore("integer_division")
	var m: int = (seconds % 3600) / 60
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % m
