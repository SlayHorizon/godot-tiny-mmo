extends CanvasLayer
## Compact pickup feed (client only) — the Genshin-style answer to loot: small
## [icon] Name ×N pills on the LEFT edge, one row per item, self-coalescing
## (another pickup of the same item bumps the ×N + pulses instead of stacking a
## new row). Replaces the "Looted 1 Tooth" text lines that used to bloat the
## kill cards (docs/notifications.md, toast-lane rework). Purely cosmetic —
## never gameplay-authoritative.
##   LootFeed.add_item(item_id, amount, fallback_name)

## Rows on screen at once (oldest dropped past this).
const MAX_ROWS: int = 6
## Seconds a row stays after its last bump.
const DWELL_S: float = 2.8

var _column: VBoxContainer
## item_id -> {"row": PanelContainer, "label": Label, "count": int}
var _active: Dictionary = {}


func _ready() -> void:
	# Mirrors Toaster: client-only UI.
	if not GameMode.is_client():
		queue_free()
		return
	layer = 90 # Under Announcer (110) and Toaster (128).
	_column = VBoxContainer.new()
	_column.anchor_top = 0.4
	_column.anchor_bottom = 0.4
	_column.offset_left = 12.0
	_column.offset_right = 260.0
	_column.add_theme_constant_override(&"separation", 4)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)


## Feed one pickup. Resolves icon + pretty name from the items registry
## ([param fallback_name] covers unresolvable ids, e.g. content mid-refresh).
func add_item(item_id: int, amount: int, fallback_name: String = "") -> void:
	if _column == null or amount <= 0:
		return

	# Gold gets its coin-flip tick (quiet, slight pitch wobble so streams don't
	# machine-gun one identical sample).
	if item_id == Economy.gold_id():
		UISound.play(UISound.COIN, randf_range(0.95, 1.08), -8.0)

	# Same item already showing: bump the count, pulse, keep it alive longer.
	if _active.has(item_id):
		var entry: Dictionary = _active[item_id]
		var row: PanelContainer = entry.get("row")
		if is_instance_valid(row):
			entry["count"] = int(entry["count"]) + amount
			(entry["label"] as Label).text = "%s ×%d" % [str(entry["name"]), int(entry["count"])]
			_pulse(row)
			_restart_dwell(row)
			return
		_active.erase(item_id) # freed — build fresh below

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	var display_name: String = str(item.item_name) if item != null else fallback_name
	var icon_texture: Texture2D = item.item_icon if item != null else null

	while _column.get_child_count() >= MAX_ROWS:
		var oldest: Node = _column.get_child(0)
		_column.remove_child(oldest)
		oldest.queue_free()

	var row: PanelContainer = PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.modulate.a = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.82)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	row.add_theme_stylebox_override(&"panel", style)

	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var icon_host: Control = Control.new()
	icon_host.custom_minimum_size = Vector2(26, 26)
	icon_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon_host)
	PixelIcon.mount(icon_host, icon_texture)

	var label: Label = Label.new()
	label.text = display_name if amount == 1 else "%s ×%d" % [display_name, amount]
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_color_override(&"font_color", Color(0.92, 0.93, 0.97))
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(label)

	_column.add_child(row)
	# Drop the coalesce entry when the row frees so the next pickup starts fresh.
	row.tree_exited.connect(func() -> void:
		if (_active.get(item_id, {}) as Dictionary).get("row") == row:
			_active.erase(item_id))
	_active[item_id] = {"row": row, "label": label, "count": amount, "name": display_name}
	_restart_dwell(row)


## Fade in (if new), dwell, fade out, free — restartable, so repeat pickups keep
## the row alive (same pattern as Toaster's dwell).
func _restart_dwell(row: Control) -> void:
	if row.has_meta(&"tween"):
		var old: Tween = row.get_meta(&"tween")
		if old != null and old.is_valid():
			old.kill()
	var tween: Tween = create_tween()
	tween.tween_property(row, ^"modulate:a", 1.0, 0.15)
	tween.tween_interval(DWELL_S)
	tween.tween_property(row, ^"modulate:a", 0.0, 0.5)
	tween.tween_callback(row.queue_free)
	row.set_meta(&"tween", tween)


func _pulse(row: Control) -> void:
	row.pivot_offset = Vector2(0.0, row.size.y * 0.5) # grow from the left edge
	var tween: Tween = create_tween()
	tween.tween_property(row, ^"scale", Vector2(1.08, 1.08), 0.08)
	tween.tween_property(row, ^"scale", Vector2.ONE, 0.08)
