@tool
class_name GatewayTheme
extends Theme

## A self-contained gateway palette. It HOLDS the palette as exported data (accent
## idle/active, surface, text) + the backdrop art, AND bakes the matching Theme
## styleboxes from that data via rebuild(). Edit a colour in the inspector and press
## "Rebuild styleboxes" to re-bake (or re-run the generator). At runtime it's just
## loaded — never rebuilt — and assigned to Gateway.theme; $Background reads
## `background`. Each .tres is the single source of truth for its own palette.

@export var palette_name: StringName

@export_group("Palette")
@export var idle: Color = Color(0.72, 0.56, 0.34)            ## accent at rest
@export var active: Color = Color(0.95, 0.74, 0.44)          ## accent on hover/focus
@export var surface: Color = Color(0.04, 0.047, 0.066, 0.93) ## panel / control fill
@export var text: Color = Color(0.929, 0.894, 0.820)         ## font colour (cream)

@export_group("Art")
@export var background: Texture2D
@export var frame_texture: Texture2D  ## neutral frame, tinted per-state via modulate

@export_tool_button("Rebuild styleboxes") var _rebuild_action: Callable = rebuild

const THEME_DIR: String = "res://source/client/ui/themes/gateway/"


## Available palette slugs (filename sans gateway_ / .tres), sorted. Cheap — lists
## names without loading the resources. Used by the Settings palette dropdown and
## as the canonical key set the gateway loads themes under.
static func list_palettes() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir: DirAccess = DirAccess.open(THEME_DIR)
	if dir == null:
		return out
	for file: String in dir.get_files():
		var file_name: String = file.trim_suffix(".remap")  # exported resources carry .remap
		if file_name.ends_with(".tres"):
			out.append(StringName(file_name.trim_prefix("gateway_").trim_suffix(".tres")))
	out.sort()
	return out


## Bake all Theme items from the palette properties above. Editor-time only —
## runtime just loads the already-baked result.
func rebuild() -> void:
	clear()

	# Default Button — procedural themed border (cards, flyout buttons, …).
	_button_states("Button", _flat(_a(surface, 0.6), idle, 0.6, 5, 8), _flat(_hover(0.92), active, 0.95, 5, 8))
	_button_fonts("Button")

	# FrameButton — the wide neutral frame texture, tinted per state.
	set_type_variation("FrameButton", "Button")
	set_stylebox("normal", "FrameButton", _tex(idle))
	var frame_active: StyleBoxTexture = _tex(active)
	set_stylebox("hover", "FrameButton", frame_active)
	set_stylebox("pressed", "FrameButton", frame_active)
	set_stylebox("focus", "FrameButton", frame_active)
	_button_fonts("FrameButton")

	# Chip — small obsidian (Settings gear / Back).
	set_type_variation("Chip", "Button")
	_button_states("Chip", _flat(_a(surface, 0.85), idle, 0.6, 6, 6), _flat(_hover(0.95), active, 0.95, 6, 6))
	_button_fonts("Chip")

	# PanelContainer — obsidian; FloatingPanel variation = transparent.
	var panel: StyleBoxFlat = _flat(surface, idle, 0.3, 8, -1)
	panel.content_margin_left = 26.0
	panel.content_margin_right = 26.0
	panel.content_margin_top = 20.0
	panel.content_margin_bottom = 20.0
	set_stylebox("panel", "PanelContainer", panel)
	set_type_variation("FloatingPanel", "PanelContainer")
	set_stylebox("panel", "FloatingPanel", StyleBoxEmpty.new())

	# LineEdit.
	set_stylebox("normal", "LineEdit", _flat(_a(surface, 0.85), idle, 0.4, 5, 8))
	set_stylebox("focus", "LineEdit", _flat(_a(surface, 0.85), active, 0.9, 5, 8))
	set_color("font_color", "LineEdit", text)
	set_color("caret_color", "LineEdit", active)

	# Label — text colour + a soft shadow for legibility over the backdrop.
	set_color("font_color", "Label", text)
	set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.7))
	set_constant("shadow_offset_x", "Label", 0)
	set_constant("shadow_offset_y", "Label", 2)

	# Separators — full-width default, short-centred TitleDivider.
	set_stylebox("separator", "HSeparator", _line(active, 0.4, 0.0, 0.0))
	set_type_variation("TitleDivider", "HSeparator")
	set_stylebox("separator", "TitleDivider", _line(active, 0.5, -90.0, -90.0))

	# CheckBox (show-password).
	set_color("font_color", "CheckBox", text)
	set_color("font_hover_color", "CheckBox", text)
	set_color("font_pressed_color", "CheckBox", text)


func _button_states(type: String, normal: StyleBox, hover: StyleBox) -> void:
	set_stylebox("normal", type, normal)
	set_stylebox("hover", type, hover)
	set_stylebox("pressed", type, hover)
	set_stylebox("focus", type, hover)


func _button_fonts(type: String) -> void:
	set_color("font_color", type, text)
	set_color("font_hover_color", type, text)
	set_color("font_pressed_color", type, text)
	set_color("font_focus_color", type, text)


func _flat(bg: Color, border: Color, border_a: float, corner: int, margin: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = Color(border.r, border.g, border.b, border_a)
	s.set_corner_radius_all(corner)
	if margin >= 0:
		s.set_content_margin_all(float(margin))
	return s


func _tex(modulate: Color) -> StyleBoxTexture:
	var s: StyleBoxTexture = StyleBoxTexture.new()
	s.texture = frame_texture
	s.modulate_color = modulate
	s.content_margin_left = 20.0
	s.content_margin_right = 20.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s


func _line(c: Color, a: float, grow_b: float, grow_e: float) -> StyleBoxLine:
	var s: StyleBoxLine = StyleBoxLine.new()
	s.color = Color(c.r, c.g, c.b, a)
	s.thickness = 1
	s.grow_begin = grow_b
	s.grow_end = grow_e
	return s


## surface colour at a given alpha.
func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)


## a slightly-lightened surface for hover fills, at a given alpha.
func _hover(alpha: float) -> Color:
	var c: Color = surface.lightened(0.07)
	c.a = alpha
	return c
