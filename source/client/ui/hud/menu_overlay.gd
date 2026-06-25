extends Control
## Right-side HUD menu launcher: a Genshin-style GRID of menu tiles (icon above label), built in code
## and routed through ClientState signals so it stays decoupled from the HUD script. A dim backdrop
## catches click-away taps. Opens/closes with a slide + fade (see open/close).
##
## SCALES by design — a 4-wide tile grid holds many menus where the old vertical text list ran out of
## height, and a ScrollContainer absorbs overflow. To ADD a menu: an entry below (label + the menu
## folder under ui/menus/) + its menu scene, and drop a `<label>.png` (lowercased) into
## assets/sprites/ui/menu_icons/ — it auto-loads as the tile icon (see _make_tile). No PNG = label-only.

## All launcher tiles in ONE ordered list, GROUPED into rows of 4 by category (You / Social / World /
## Other) so each grid row reads as one category. Each entry: a label, and the menu folder under
## ui/menus/ to open ("" = the special own-profile entry; NO "menu" key = a placeholder with no target
## yet, which toasts "coming soon"). Icons auto-load from ICON_DIR by lowercased label. Placeholders show
## in exports too (a full, even grid beats a half-empty one); promote one to a real menu by adding "menu".
## Reorder freely: the only rule is keep it 4 per category so the rows stay aligned.
const MENU_ENTRIES: Array[Dictionary] = [
	# You
	{"label": "Profile",     "menu": ""},
	{"label": "Character",   "menu": "character"},
	{"label": "Quests",      "menu": "quests"},
	{"label": "Inventory",   "menu": "inventory"},
	# Social
	{"label": "Friends",     "menu": "friends"},
	{"label": "Mail",        "menu": "mail"},
	{"label": "Guild",       "menu": "guild"},
	{"label": "Leaderboard", "menu": "leaderboard"},
	# World
	{"label": "Map"},
	{"label": "Achievements"},
	{"label": "Bestiary"},
	{"label": "House"},
	# Other + Settings
	{"label": "Shop"},
	{"label": "Help",        "menu": "help"},
	{"label": "Redeem",      "menu": "redeem"},
	{"label": "Settings",    "menu": "settings"},
]

## Tiles per row — 4, Genshin-style. Tiles are sized for TOUCH (mobile).
const GRID_COLUMNS: int = 4

## Icon style folder — flip between the flat and drop-shadow sets (both kept in-project) by changing
## this one line: "res://assets/sprites/ui/menu_icons/" (flat) or ".../menu_icons_shadow/" (shadow).
const ICON_DIR: String = "res://assets/sprites/ui/menu_icons_shadow/"

## Right-dock geometry (px from the screen's right edge). Full-height panel flush to top/right/bottom
## (mirrors the left-docked chat); slides in from PANEL_SLIDE further right while fading. Wide enough that
## 4 columns give bigger ~square tiles with room for long labels.
const PANEL_OFFSET_LEFT: float = -456.0
const PANEL_OFFSET_RIGHT: float = 0.0
const PANEL_SLIDE: float = 48.0

var _panel: Control
var _tween: Tween
# The Mail tile's label, captured at build so open() can badge it with the unread count.
var _mail_label: Label
# Semi-transparent tile backgrounds (built once, shared) — they blend with the see-through panel;
# hover/pressed brighten for feedback.
var _tile_normal: StyleBoxFlat
var _tile_hover: StyleBoxFlat
var _tile_pressed: StyleBoxFlat


func _ready() -> void:
	_build()
	hide()


func _build() -> void:
	_build_tile_styles()

	# Dim backdrop — a tap outside the panel closes it + the game underneath doesn't get the click.
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.5)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(dim)

	# Right-docked, full-height side panel (no floating card) so it reads consistently with the chat.
	_panel = Control.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = PANEL_OFFSET_LEFT
	_panel.offset_right = PANEL_OFFSET_RIGHT
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	add_child(_panel)

	# Full-bleed backdrop: dark + opaque anchored at the RIGHT (screen) edge, fading lighter and more
	# transparent toward the centre where the panel meets empty screen. Mirrors the chat on the opposite
	# side. LINEAR-filtered (a smooth gradient, not pixel art; icons keep the project's NEAREST default).
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.07, 0.075, 0.09, 0.95), Color(0.13, 0.14, 0.16, 0.35)])
	var grad_tex: GradientTexture2D = GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(1.0, 0.5)
	grad_tex.fill_to = Vector2(0.0, 0.5)
	var grad_rect: TextureRect = TextureRect.new()
	grad_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad_rect.texture = grad_tex
	grad_rect.stretch_mode = TextureRect.STRETCH_SCALE
	grad_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	grad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(grad_rect)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 8)
	margin.add_child(vbox)

	# No title — the icon tiles speak for themselves. Scrollable so the grid never overflows.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var grid: GridContainer = GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(grid)

	# Every tile shows, placeholders included, so the grid stays a full even 4-per-row block. Placeholders
	# toast "coming soon" on tap (see _make_tile).
	for entry: Dictionary in MENU_ENTRIES:
		grid.add_child(_make_tile(entry))

	# Drag the tile grid to scroll on touch/mouse; tile taps still open their menus.
	DragScroll.enable(scroll)

	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.pressed.connect(close)
	vbox.add_child(close_button)


## Shared tile cards: opaque enough to read as distinct against the gradient panel (the old 0.4-alpha
## boxes melted into it), with a subtle light border, plus hover/pressed brightening for feedback.
func _build_tile_styles() -> void:
	_tile_normal = _tile_box(Color(0.20, 0.23, 0.31, 0.88))
	_tile_hover = _tile_box(Color(0.29, 0.34, 0.45, 0.95))
	_tile_pressed = _tile_box(Color(0.13, 0.15, 0.20, 0.96))


func _tile_box(c: Color) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(6)
	b.set_border_width_all(1)
	b.border_color = Color(0.45, 0.50, 0.62, 0.55)
	return b


## One menu tile, Genshin-style: a pixel-art icon up top, a bottom-pinned label. The icon is a direct,
## mouse-ignored child (NOT in a container) so we can pin its GLOBAL position to whole pixels — THE fix
## for the sub-pixel artifact: container centering / KEEP_CENTERED park the texture on a half-pixel,
## which nearest-samples into uneven rows even at 1:1. A dev filler (no "menu" key) toasts "coming soon".
func _make_tile(entry: Dictionary) -> Button:
	var tile: Button = Button.new()
	tile.custom_minimum_size = Vector2(0, 90)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.clip_contents = true
	tile.add_theme_stylebox_override(&"normal", _tile_normal)
	tile.add_theme_stylebox_override(&"hover", _tile_hover)
	tile.add_theme_stylebox_override(&"pressed", _tile_pressed)
	tile.add_theme_stylebox_override(&"focus", _tile_hover)

	# Label pinned across the bottom, centered.
	var label: Label = Label.new()
	label.text = str(entry["label"])
	if str(entry["label"]) == "Mail":
		_mail_label = label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_constant_override(&"outline_size", 4)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -32.0
	label.offset_bottom = -8.0
	tile.add_child(label)

	# Icon: NEAREST pixel art at NATIVE size (the codebase's crisp-pixel convention — see
	# wardrobe_menu/territory_flag), centered MANUALLY on WHOLE global pixels. Re-pinned whenever the
	# tile's rect changes (layout/resize); the open-slide only knocks it off-grid mid-animation, after
	# which it lands back on whole pixels — crisp. This is what kills the half-pixel sampling at 1:1.
	var icon_path: String = str(entry.get("icon", ""))
	if icon_path.is_empty():
		icon_path = ICON_DIR + str(entry["label"]).to_lower() + ".png"
	if ResourceLoader.exists(icon_path):
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = load(icon_path)
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
		icon_rect.size = icon_rect.texture.get_size()
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(icon_rect)
		var snap_icon: Callable = func() -> void:
			if not icon_rect.is_inside_tree():
				return
			var ts: Vector2 = icon_rect.texture.get_size()
			icon_rect.global_position = (tile.global_position + Vector2((tile.size.x - ts.x) * 0.5, 13.0)).round()
		tile.item_rect_changed.connect(snap_icon)

	if entry.has("menu"):
		tile.pressed.connect(_on_entry_pressed.bind(str(entry["menu"])))
	else: # dev-only filler — no real menu behind it
		tile.pressed.connect(func() -> void: Toaster.toast("Coming soon", 1.5))
	return tile


func _on_entry_pressed(menu_name: String) -> void:
	close()
	if menu_name.is_empty():
		ClientState.player_profile_requested.emit(0)  # 0 = own profile
	else:
		ClientState.open_menu_requested.emit(StringName(menu_name), null)


## Slide the card in from the right edge + fade. Clearly reads as "opened" (a plain alpha fade was too
## subtle). Kills any in-flight tween so a fast re-open/close can't fight itself.
func open() -> void:
	_refresh_mail_badge()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	show()
	modulate.a = 0.0
	_panel.offset_left = PANEL_OFFSET_LEFT + PANEL_SLIDE
	_panel.offset_right = PANEL_OFFSET_RIGHT + PANEL_SLIDE
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, ^"modulate:a", 1.0, 0.18)
	_tween.tween_property(_panel, ^"offset_left", PANEL_OFFSET_LEFT, 0.18)
	_tween.tween_property(_panel, ^"offset_right", PANEL_OFFSET_RIGHT, 0.18)


## The open effect in reverse: slide back out to the right + fade, THEN hide.
func close() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, ^"modulate:a", 0.0, 0.16)
	_tween.tween_property(_panel, ^"offset_left", PANEL_OFFSET_LEFT + PANEL_SLIDE, 0.16)
	_tween.tween_property(_panel, ^"offset_right", PANEL_OFFSET_RIGHT + PANEL_SLIDE, 0.16)
	_tween.chain().tween_callback(hide)


## Fetch the unread-mail count and badge the Mail tile ("Mail (N)" / "Mail").
## Called on each launcher open, so the badge stays fresh without any login/push
## wiring — opening a mail closes the launcher, and reopening it re-fetches.
func _refresh_mail_badge() -> void:
	if _mail_label == null or InstanceClient.current == null:
		return
	var result: Array = await Client.request_data_await(&"mail.unread_count", {}, String(InstanceClient.current.name))
	if not is_instance_valid(_mail_label):
		return
	var count: int = int((result[0] as Dictionary).get("count", 0)) if result[1] == OK else 0
	_mail_label.text = "Mail (%d)" % count if count > 0 else "Mail"
