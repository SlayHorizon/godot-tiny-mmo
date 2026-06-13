extends HBoxContainer
## Status strip: one icon per active buff / debuff, plus an in-combat marker,
## rebuilt from the server's 1 Hz status.sync push. Each icon carries a
## remaining-seconds badge and a tooltip; the local clock counts the badge
## down between pushes so it ticks smoothly instead of jumping once a second.
## Pure display — every node is MOUSE_FILTER_IGNORE.

const ICON_DIR: String = "res://assets/sprites/ui/status/"
const TILE: float = 30.0

## Per-status art. Buffs fall back to the generic up-arrow, debuffs to the
## generic down-arrow, so a new effect shows SOMETHING before it gets bespoke
## art. Combat is its own fixed marker.
const BUFF_ICONS: Dictionary = {
	&"mana_regen": "manaregen.png",
	&"move_speed": "buff.png",
}
const DEBUFF_ICONS: Dictionary = {
	&"burn": "burn.png",
	&"poison": "poison.png",
	&"slow": "debuff.png",
}
const BUFF_FALLBACK: String = "buff.png"
const DEBUFF_FALLBACK: String = "debuff.png"
const COMBAT_ICON: String = "combat.png"

## Friendly tooltip names for the stat a buff raises.
const STAT_LABELS: Dictionary = {
	&"mana_regen": "Mana Regen",
	&"move_speed": "Move Speed",
	&"ad": "Attack Damage",
	&"ap": "Ability Power",
	&"armor": "Armor",
	&"mr": "Magic Resist",
}

## One-line explanations shown on hover (desktop) AND tap (mobile) so players
## learn what each icon means, LoL-style. Buffs/debuffs without a bespoke line
## fall back to a generated one.
const DESCRIPTIONS: Dictionary = {
	&"combat": "In Combat — armor is locked (weapons still swap freely).",
	&"burn": "Burning — taking fire damage every second.",
	&"poison": "Poisoned — taking damage every second.",
	&"slow": "Slowed — reduced movement speed.",
	&"mana_regen": "Mana Tonic — your mana regenerates faster.",
	&"move_speed": "Hastened — increased movement speed.",
}

## How long the tap-to-read label lingers on mobile (no hover there).
const TAP_LABEL_S: float = 2.5

var _icon_cache: Dictionary[String, Texture2D] = {}
## Live tiles: key -> {"node", "label"(or null), "deadline_ms"}. Keyed so the
## per-frame countdown finds badges AND so a stable status set is NOT torn down
## and rebuilt every push (that churn freed the tap label → crash, and reset
## hover/tap before you could read it).
var _tiles: Dictionary = {}
## Ordered keys of the currently-built tiles — compared against each push to
## decide rebuild vs. just refresh the countdown deadlines.
var _order: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 4)
	Client.subscribe(&"status.sync", _on_status_sync)


func _on_status_sync(payload: Dictionary) -> void:
	# Flatten the payload into ordered tile specs: {key, icon, desc, remaining}.
	var specs: Array[Dictionary] = []
	if bool(payload.get("in_combat", false)):
		specs.append({"key": "combat", "icon": COMBAT_ICON, "desc": _describe(&"combat", "In combat."), "remaining": -1})
	for buff: Dictionary in payload.get("buffs", []):
		var bid: StringName = StringName(str(buff.get("id", "")))
		specs.append({
			"key": "buff:" + String(bid), "icon": BUFF_ICONS.get(bid, BUFF_FALLBACK),
			"desc": _describe(bid, "%s boosted." % str(STAT_LABELS.get(bid, String(bid).capitalize()))),
			"remaining": int(buff.get("remaining", 0)),
		})
	for debuff: Dictionary in payload.get("debuffs", []):
		var did: StringName = StringName(str(debuff.get("id", "")))
		specs.append({
			"key": "debuff:" + String(did), "icon": DEBUFF_ICONS.get(did, DEBUFF_FALLBACK),
			"desc": _describe(did, "%s — harmful effect." % String(did).capitalize()),
			"remaining": int(debuff.get("remaining", 0)),
		})

	var new_order: Array[String] = []
	for spec: Dictionary in specs:
		new_order.append(spec["key"])

	# Stable set → just re-arm the countdown deadlines (server is authoritative
	# on remaining), keeping tiles/tooltips/tap-label alive. No teardown.
	if new_order == _order:
		var now: int = Time.get_ticks_msec()
		for spec: Dictionary in specs:
			var info: Dictionary = _tiles.get(spec["key"], {})
			if info.get("label") != null:
				info["deadline_ms"] = now + int(spec["remaining"]) * 1000
		return

	# Set changed → rebuild ONLY the tracked tile nodes (never the tap label).
	for key: String in _tiles:
		var node: Node = _tiles[key]["node"]
		if is_instance_valid(node):
			node.queue_free()
	_tiles.clear()
	_order = new_order
	for spec: Dictionary in specs:
		_add_tile(spec["key"], spec["icon"], spec["desc"], int(spec["remaining"]))


func _describe(id: StringName, fallback: String) -> String:
	return str(DESCRIPTIONS.get(id, fallback))


## [param remaining] < 0 = no countdown (the combat marker just shows/hides).
func _add_tile(key: String, icon_file: String, description: String, remaining: int) -> void:
	var tile: TextureRect = TextureRect.new()
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.texture = _load_icon(icon_file)
	tile.tooltip_text = description # desktop hover
	# PASS (not IGNORE): enables the hover tooltip + tap events, but isn't STOP,
	# so the combat input gate still lets you attack while the cursor is over an
	# icon. Tap shows the same text for mobile (no hover there).
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			_show_tap_label(description)
	)
	add_child(tile)

	if remaining < 0:
		_tiles[key] = {"node": tile, "label": null, "deadline_ms": 0}
		return
	var badge: Label = Label.new()
	badge.add_theme_font_size_override(&"font_size", 11)
	badge.add_theme_color_override(&"font_color", Color(1, 1, 1))
	badge.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	badge.add_theme_constant_override(&"outline_size", 3)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tiles[key] = {
		"node": tile,
		"label": badge,
		"deadline_ms": Time.get_ticks_msec() + remaining * 1000,
	}
	_paint_badge(badge, remaining)


func _process(_delta: float) -> void:
	if _tiles.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for key: String in _tiles:
		var info: Dictionary = _tiles[key]
		if info["label"] == null:
			continue # countdown-less marker (in-combat)
		var secs: int = int(ceil((int(info["deadline_ms"]) - now) / 1000.0))
		_paint_badge(info["label"], maxi(0, secs))


func _paint_badge(badge: Label, secs: int) -> void:
	badge.text = str(secs) if secs > 0 else ""


func _load_icon(file_name: String) -> Texture2D:
	if not _icon_cache.has(file_name):
		_icon_cache[file_name] = load(ICON_DIR + file_name) as Texture2D
	return _icon_cache[file_name]


## Transient read-out under the strip — the mobile stand-in for a hover
## tooltip. Reuses one label; each tap restarts its fade.
var _tap_label: Label
var _tap_tween: Tween

func _show_tap_label(text: String) -> void:
	if _tap_label == null:
		_tap_label = Label.new()
		_tap_label.add_theme_font_size_override(&"font_size", 12)
		_tap_label.add_theme_color_override(&"font_color", Color(1, 1, 1))
		_tap_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
		_tap_label.add_theme_constant_override(&"outline_size", 4)
		_tap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tap_label.position = Vector2(0, TILE + 4)
		add_child(_tap_label)
	_tap_label.text = text
	_tap_label.modulate.a = 1.0
	_tap_label.visible = true
	if _tap_tween != null and _tap_tween.is_valid():
		_tap_tween.kill()
	_tap_tween = create_tween()
	_tap_tween.tween_interval(TAP_LABEL_S)
	_tap_tween.tween_property(_tap_label, ^"modulate:a", 0.0, 0.4)
	_tap_tween.tween_callback(func() -> void:
		if is_instance_valid(_tap_label):
			_tap_label.visible = false
	)
