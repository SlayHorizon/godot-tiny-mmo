@tool
@icon("res://assets/node_icons/color/icon_map_colored.png")
class_name Map
extends Node2D


enum AOIMode {
	NONE,
	GRID,
}

enum ZoneMode {
	SAFE,
	PVP,
}

enum ZoneModifiers {
	ARENA,
	NO_SKILL,
	NO_MOUNT,
	NO_SUMMONS
}

@export_group("Area Of Interest")
@export var aoi_mode: AOIMode = AOIMode.NONE
@export var aoi_cell_size: Vector2i = Vector2i(250, 250)
@export var aoi_visible_radius_cells: int = 2
@export var aoi_margin_cells: int = 1

@export_subgroup("Editor Debug Preview")
@export var preview_aoi: bool = true
@export var preview_aoi_follow_mouse: bool = true
@export var preview_rect := Rect2(-4096, -4096, 8192, 8192)
@export var aoi_origin: Vector2i = Vector2i.ZERO
@export var aoi_test_point := Vector2.ZERO

@export_group("Zones")
@export var default_mode: ZoneMode = ZoneMode.SAFE
@export_flags("NO_SKILL", "NO_CONSUMABLES", "NO_MOUNT", "NO_SUMMONS") var default_modifiers: int = 0
# Zoning grid (independent from AOI)
@export var zone_cell_size: Vector2i = Vector2i(64, 64)
@export var zone_origin: Vector2i = Vector2i.ZERO

@export_group("")
@export var replicated_props_container: ReplicatedPropsContainer
@export var map_background_color := Color(0,0,0)

var warpers: Dictionary[int, Warper]


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint():
		return
	
	for child: Node in get_children():
		if child is Warper:
			var warper_id: int = child.warper_id
			warpers[warper_id] = child

	if OS.has_feature("client"):
		RenderingServer.set_default_clear_color(map_background_color)


func get_spawn_position(warper_id: int = 0) -> Vector2:
	if warpers.has(warper_id):
		return warpers[warper_id].global_position
	return Vector2.ZERO


func override_map_rules(instance_resource: InstanceResource) -> void:
	# Can be implemented later.
	# Could override fields when instances of the same map need different rules.
	pass


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if preview_aoi:
		_draw_aoi_preview()


func _draw_aoi_preview() -> void:
	var grid_color: Color = Color(1, 1, 1, 0.18)
	var visible_fill: Color = Color(0.15, 0.75, 1.0, 0.14)
	var visible_border: Color = Color(0.15, 0.85, 1.0, 0.95)
	var margin_border: Color = Color(0.15, 0.75, 1.0, 0.70)

	var zoom_scale: float = EditorInterface.get_editor_viewport_2d().global_canvas_transform.get_scale().x
	var px: float = 2.0 / zoom_scale
	var w_grid: float = clamp(1.25 * px, 0.75, 8.0)
	var w_border: float = clamp(2.25 * px, 1.0, 14.0)
	var dash_step: float = clamp(16.0 * px, 8.0, 32.0)

	# 1 Grid lines (aligned to origin)
	var x0: float = _snap_floor_to_cell(preview_rect.position.x, aoi_cell_size.x, aoi_origin.x)
	var y0: float = _snap_floor_to_cell(preview_rect.position.y, aoi_cell_size.y, aoi_origin.y)
	var x1: float = preview_rect.position.x + preview_rect.size.x
	var y1: float = preview_rect.position.y + preview_rect.size.y

	var x: float = x0
	while x <= x1:
		draw_line(Vector2(x, y0), Vector2(x, y1), grid_color, w_grid, true)
		x += float(aoi_cell_size.x)

	var y: float = y0
	while y <= y1:
		draw_line(Vector2(x0, y), Vector2(x1, y), grid_color, w_grid, true)
		y += float(aoi_cell_size.y)

	# 2 Visible window + margin ring around a test point
	var origin_v: Vector2 = Vector2(aoi_origin)
	var p: Vector2 = get_global_mouse_position() if preview_aoi_follow_mouse else aoi_test_point
	var rel: Vector2 = p - origin_v
	var cell_v: Vector2 = (rel / Vector2(aoi_cell_size)).floor()
	var cell: Vector2i = Vector2i(cell_v)

	var r: int = aoi_visible_radius_cells
	var m: int = max(0, aoi_margin_cells)

	var vis_rect: Rect2 = Rect2(
		origin_v + Vector2(cell - Vector2i(r, r)) * Vector2(aoi_cell_size),
		Vector2((2 * r + 1) * aoi_cell_size.x, (2 * r + 1) * aoi_cell_size.y)
	)
	var mar_rect: Rect2 = Rect2(
		origin_v + Vector2(cell - Vector2i(r + m, r + m)) * Vector2(aoi_cell_size),
		Vector2((2 * (r + m) + 1) * aoi_cell_size.x, (2 * (r + m) + 1) * aoi_cell_size.y)
	)

	# Fill visible window
	draw_rect(vis_rect, visible_fill, true)
	# Borders (dashed margin)
	_draw_rect_border(vis_rect, visible_border, w_border)
	if m > 0:
		_draw_rect_border(mar_rect, margin_border, w_border, true, dash_step)

	# Origin crosshair
	_draw_cross(origin_v, Color(1, 1, 0, 0.9), 10.0 * px, max(1.0, 2.0 * px))
	_draw_cross(p, Color(1, 1, 0, 0.9), 10.0 * px, max(1.0, 2.0 * px))


func _snap_floor_to_cell(v: float, cell: int, origin: int) -> float:
	var rel: float = v - float(origin)
	return float(origin) + floor(rel / float(cell)) * float(cell)


func _draw_rect_border(r: Rect2, color: Color, width: float, dashed: bool=false, step: float=16.0) -> void:
	if dashed:
		var pts: Array[Vector2] = [
			r.position,
			r.position + Vector2(r.size.x, 0.0),
			r.position + r.size,
			r.position + Vector2(0.0, r.size.y)
		]
		for i in pts.size():
			_draw_dashed_line(pts[i], pts[(i + 1) % pts.size()], color, width, step)
	else:
		draw_rect(r, color, false, width)


func _draw_dashed_line(a: Vector2, b: Vector2, color: Color, width: float, step: float) -> void:
	var dir: Vector2 = b - a
	var len: float = dir.length()
	if len <= 0.001:
		return
	var n: int = int(len / step)
	if n <= 0:
		draw_line(a, b, color, width, true)
		return
	var v: Vector2 = dir / float(n)
	for i in n:
		if (i % 2) == 0:
			draw_line(a + v * float(i), a + v * float(i + 1), color, width, true)


func _draw_cross(c: Vector2, color: Color, size: float, width: float) -> void:
	draw_line(c + Vector2(-size, 0.0), c + Vector2(size, 0.0), color, width, true)
	draw_line(c + Vector2(0.0, -size), c + Vector2(0.0, size), color, width, true)


# Returns defaults + every ZonePatch2D polygon in MAP space.
# This is the only thing SSM needs at startup to build a zone grid.
func get_zone_authoring_data() -> Dictionary:
	var patches: Array = []
	var nodes: Array[Node] = find_children("*", "ZonePatch2D", true)

	for n: Node in nodes:
		var z: ZonePatch2D = n as ZonePatch2D
		if not z.enabled:
			continue

		var payload: Dictionary = z.get_bake_payload()  # local polys + z.global_transform
		var polys_local: Array = payload.get("polygons_local", [])
		var xf: Transform2D = payload.get("global_transform", Transform2D.IDENTITY)

		var polys_world: Array[PackedVector2Array] = _polys_local_to_world(polys_local, xf)

		patches.append({
			"name_id": z.name_id,
			"priority": z.priority,
			"mode_override": z.mode_override,
			"add_modifiers": z.add_modifiers,
			"remove_modifiers": z.remove_modifiers,
			"polygons_world": polys_world,
		})

	return {
		"default_mode": default_mode,
		"default_modifiers": default_modifiers,
		"zone_cell_size": zone_cell_size,
		"zone_origin": zone_origin,
		"patches": patches,
	}

# Utility: convert a list of local-space polygons to map-space using a transform.
func _polys_local_to_world(polys_local: Array, xf: Transform2D) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for pl_any in polys_local:
		var pl: PackedVector2Array = pl_any
		var n: int = pl.size()
		if n < 3:
			continue
		var pw: PackedVector2Array = PackedVector2Array()
		pw.resize(n)
		for i in n:
			pw[i] = xf * pl[i]
		out.append(pw)
	return out
