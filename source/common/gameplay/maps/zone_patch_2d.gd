@tool
class_name ZonePatch2D
extends Node2D

## Deleted during export
## Authoring-time patch: one shape + rules + priority (drawn in editor, baked later).

enum ModeOverride { INHERIT, SAFE, PVP }

@export var enabled: bool = true
@export var name_id: StringName = &""
@export var priority: int = 0
@export var mode_override: ModeOverride = ModeOverride.INHERIT
@export_flags("NO_SKILL", "NO_CONSUMABLES", "NO_MOUNT", "NO_SUMMONS") var add_modifiers: int = 0
@export_flags("NO_SKILL", "NO_CONSUMABLES", "NO_MOUNT", "NO_SUMMONS") var remove_modifiers: int = 0

@export var auto_tint: bool = true
@export var debug_tint: Color = Color(1, 0, 0, 0.16) # used when auto_tint = false

func _process(_dt: float) -> void:
	if Engine.is_editor_hint():
		# Keep child fills in sync with mode/debug tint while editing.
		_apply_fill_tint_to_children(_pick_tint() if auto_tint else debug_tint)
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or not enabled:
		return

	var polygons: Array[PackedVector2Array] = _collect_polygons()
	if polygons.is_empty():
		return

	# Outline only (fills are handled by Polygon2D.color)
	var tint: Color = _pick_tint() if auto_tint else debug_tint
	var outline: Color = tint.darkened(0.35)

	var zoom_scale: float = EditorInterface.get_editor_viewport_2d().global_canvas_transform.get_scale().x
	var pixel_scale: float = 2.0 / zoom_scale
	var outline_width: float = clamp(2.0 * pixel_scale, 1.0, 12.0)

	for poly: PackedVector2Array in polygons:
		_draw_polygon_outline(poly, outline, outline_width)


# --- Helpers

func _apply_fill_tint_to_children(tint: Color) -> void:
	for child in get_children():
		if child is Polygon2D:
			var p: Polygon2D = child
			p.color = tint


func _pick_tint() -> Color:
	match mode_override:
		ModeOverride.SAFE:
			return Color(0.25, 1.0, 0.25, 0.16) # green
		ModeOverride.PVP:
			return Color(1.0, 0.25, 0.25, 0.16) # red
		_:
			return Color(0.25, 0.65, 1.0, 0.14) # neutral (inherit)


func _collect_polygons() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for child in get_children():
		if child is Polygon2D:
			var p2: Polygon2D = child
			var xform: Transform2D = p2.transform
			var src: PackedVector2Array = p2.polygon
			var n: int = src.size()
			if n >= 3:
				var pts: PackedVector2Array = PackedVector2Array()
				pts.resize(n)
				for i in n:
					pts[i] = xform * src[i]
				out.append(pts)
	return out


func _draw_polygon_outline(poly: PackedVector2Array, color: Color, width: float) -> void:
	var count: int = poly.size()
	if count < 2:
		return
	for i in count - 1:
		draw_line(poly[i], poly[i + 1], color, width, true)
	draw_line(poly[count - 1], poly[0], color, width, true)


# Export-ready payload (local polys + transform; baker places in map space)
func get_bake_payload() -> Dictionary:
	return {
		"enabled": enabled,
		"name": name_id,
		"priority": priority,
		"mode_override": mode_override,
		"add_modifiers": add_modifiers,
		"remove_modifiers": remove_modifiers,
		"polygons_local": _collect_polygons(),
		"global_transform": global_transform,
	}
