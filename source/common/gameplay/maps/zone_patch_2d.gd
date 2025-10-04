@tool
class_name ZonePatch2D
extends Node2D

## Deleted during export
## Authoring-time patch: one shape + rules + priority (drawn in editor, baked later).

const DISABLED_COLOR: Color = Color(0.0, 0.0, 0.0, 0.25) # Dark
const SAFE_COLOR: Color = Color(0.25, 1.0, 0.25, 0.16) # Green
const PVP_COLOR: Color = Color(1.0, 0.25, 0.25, 0.16) # Red
const INHERIT_COLOR: Color = Color(0.25, 0.65, 1.0, 0.14) # Whitey (neutral)

enum ModeOverride {
	SAFE,
	PVP,
	INHERIT,
}

@export var enabled: bool = true:
	set(value):
		enabled = value
		queue_redraw()

@export var name_id: StringName = &""
@export var priority: int = 0

@export var mode_override: ModeOverride = ModeOverride.INHERIT:
	set(value):
		mode_override = value
		queue_redraw()

@export_flags("NO_SKILL", "NO_CONSUMABLES", "NO_MOUNT", "NO_SUMMONS") var add_modifiers: int = 0
@export_flags("NO_SKILL", "NO_CONSUMABLES", "NO_MOUNT", "NO_SUMMONS") var remove_modifiers: int = 0

@export var default_tint: bool = true:
	set(value):
		if value != default_tint:
			queue_redraw()
		default_tint = value

## Used when default_tint == false
@export var custom_tint: Color = Color(1, 0, 0, 0.16):
	set(value):
		if not default_tint:
			queue_redraw()
		custom_tint = value


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var polygons: Array[PackedVector2Array]# = collect_polygons()
	#if polygons.is_empty():
		#return
	#draw_set_transform_matrix(global_transform.affine_inverse())
	# Outline only (fills are handled by Polygon2D.color)
	var tint: Color = pick_tint() if default_tint else custom_tint
	for child: Node in get_children():
		if child is Polygon2D:
			child.color = tint
			polygons.append(child.polygon
				if child.transform == Transform2D.IDENTITY else
				child.transform * child.polygon)
	var outline: Color = tint.darkened(0.35)

	var zoom_scale: float = EditorInterface.get_editor_viewport_2d().global_canvas_transform.get_scale().x
	var pixel_scale: float = 3.0 / zoom_scale
	var outline_width: float = clamp(2.0 * pixel_scale, 1.0, 12.0)
	for poly: PackedVector2Array in polygons:
		draw_polyline(poly, outline, outline_width, true)
		draw_line(poly[-1], poly[0], outline, outline_width, true)


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		update_configuration_warnings()
		queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray
	var has_polygon2d: bool = false
	for child: Node in get_children():
		if child is Polygon2D:
			has_polygon2d = true
		else:
			warnings.append("ZonePatch2D expects Polygon2D children only.")
	if not has_polygon2d:
		warnings.append("Add at least one Polygon2D child to define this patch area.")
	return warnings


func pick_tint() -> Color:
	if not enabled:
		return DISABLED_COLOR
	match mode_override:
		ModeOverride.SAFE:
			return SAFE_COLOR
		ModeOverride.PVP:
			return PVP_COLOR
		_:
			return INHERIT_COLOR


func collect_polygons() -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array]
	for polygon2d: Node in get_children():
		if not polygon2d is Polygon2D:
			continue
		polygons.append(
			#polygon2d.polygon
			#if polygon2d.transform == Transform2D.IDENTITY else
			polygon2d.global_transform * polygon2d.polygon
		)
	return polygons


# Export-ready payload (local polys + transform; baker places in map space)
func get_bake_payload() -> Dictionary:
	return {
		"enabled": enabled,
		"priority": priority,
		"mode_override": mode_override,
		"add_modifiers": add_modifiers,
		"remove_modifiers": remove_modifiers,
		"polygons": collect_polygons(),
	}
