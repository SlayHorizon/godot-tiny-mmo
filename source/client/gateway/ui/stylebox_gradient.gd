@tool
class_name StyleBoxGradientRound
extends StyleBox

@export var texture: Texture2D:
	set(v):
		texture = v
		emit_changed()

@export var border_color: Color = Color(1, 1, 1, 1):
	set(v):
		border_color = v
		emit_changed()

@export_range(0.0, 1024.0, 0.1) var border_width: float = 2.0:
	set(v):
		border_width = v
		emit_changed()

@export var corner_radius_top_left: float = 12.0:
	set(v):
		corner_radius_top_left = v
		emit_changed()

@export var corner_radius_top_right: float = 12.0:
	set(v):
		corner_radius_top_right = v
		emit_changed()

@export var corner_radius_bottom_right: float = 12.0:
	set(v):
		corner_radius_bottom_right = v
		emit_changed()

@export var corner_radius_bottom_left: float = 12.0:
	set(v):
		corner_radius_bottom_left = v
		emit_changed()

#@export_range(1, 64, 1) var segments_per_corner: int = 10:
	#set(v):
		#segments_per_corner = v
		## Avoid 0 which would degenerate arcs
		#if segments_per_corner < 1:
			#segments_per_corner = 1
		#emit_changed()

@export_range(1, 48, 1) var segments_per_corner: int = 20:
	set(v):
		segments_per_corner = max(1, v)
		emit_changed()

@export var pixel_snap: bool = true:
	set(v):
		pixel_snap = v
		emit_changed()


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect

func _get_minimum_size() -> Vector2:
	var bw = border_width
	return Vector2(bw * 2.0, bw * 2.0)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	# optional pixel snapping (helps when MSAA is low/off)
	if pixel_snap:
		rect.position.x = floor(rect.position.x) + 0.5
		rect.position.y = floor(rect.position.y) + 0.5
		rect.size.x = floor(rect.size.x)
		rect.size.y = floor(rect.size.y)

	var r = _radii_clamped(rect.size)

	# BORDER
	if border_width > 0.0 and border_color.a > 0.0:
		var outer_points = _rounded_rect_points(rect, r)
		var cols = PackedColorArray()
		cols.resize(outer_points.size())
		for i in cols.size():
			cols[i] = border_color
		RenderingServer.canvas_item_add_polygon(to_canvas_item, outer_points, cols)

	# FILL
	var inner = rect.grow(-border_width)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var inner_r = _radii_inset(r, border_width, inner.size)
	var inner_points = _rounded_rect_points(inner, inner_r)

	if texture and texture.get_rid().is_valid():
		var uvs = PackedVector2Array()
		uvs.resize(inner_points.size())
		for i in range(inner_points.size()):
			var p: Vector2 = inner_points[i]
			var u = (p.x - rect.position.x) / max(rect.size.x, 0.00001)
			var v = (p.y - rect.position.y) / max(rect.size.y, 0.00001)
			uvs[i] = Vector2(u, v)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, inner_points, PackedColorArray(), uvs, texture.get_rid())
	else:
		var fill_cols = PackedColorArray()
		fill_cols.resize(inner_points.size())
		for i in fill_cols.size():
			fill_cols[i] = Color.WHITE
		RenderingServer.canvas_item_add_polygon(to_canvas_item, inner_points, fill_cols)
#func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	## draw directly into the provided canvas item (no extra RID!)
	## — this keeps ordering correct: background first, then control text on top.
	#var r = _radii_clamped(rect.size)
#
	## 1) Border fill (outer rounded rect)
	#if border_width > 0.0 and border_color.a > 0.0:
		#var outer_points = _rounded_rect_points(rect, r)
		#var cols = PackedColorArray()
		#cols.resize(outer_points.size())
		#for i in cols.size():
			#cols[i] = border_color
		#RenderingServer.canvas_item_add_polygon(to_canvas_item, outer_points, cols)
#
	## 2) Inner gradient fill
	#var inner = rect.grow(-border_width)
	#if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		#return
#
	#var inner_r = _radii_inset(r, border_width, inner.size)
	#var inner_points = _rounded_rect_points(inner, inner_r)
#
	#if texture and texture.get_rid().is_valid():
		#var uvs = PackedVector2Array()
		#uvs.resize(inner_points.size())
		#for i in range(inner_points.size()):
			#var p: Vector2 = inner_points[i]
			#var u = (p.x - rect.position.x) / max(rect.size.x, 0.00001)
			#var v = (p.y - rect.position.y) / max(rect.size.y, 0.00001)
			#uvs[i] = Vector2(u, v)
#
		#RenderingServer.canvas_item_add_polygon(
			#to_canvas_item,
			#inner_points,
			#PackedColorArray(),
			#uvs,
			#texture.get_rid()
		#)
	#else:
		#var fill_cols = PackedColorArray()
		#fill_cols.resize(inner_points.size())
		#for i in fill_cols.size():
			#fill_cols[i] = Color.WHITE
		#RenderingServer.canvas_item_add_polygon(to_canvas_item, inner_points, fill_cols)


static func _arc(center: Vector2, radius: float, from_angle: float, to_angle: float, segments: int) -> PackedVector2Array:
	var pts = PackedVector2Array()
	if radius <= 0.0 or segments <= 0:
		pts.push_back(center)
		return pts
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		var ang = lerp(from_angle, to_angle, t)
		pts.push_back(center + Vector2(cos(ang), sin(ang)) * radius)
	return pts

func _rounded_rect_points(rect: Rect2, r: Dictionary) -> PackedVector2Array:
	var tl: float = r.tl
	var tr: float = r.tr
	var br: float = r.br
	var bl: float = r.bl

	var left = rect.position.x
	var top = rect.position.y
	var right = rect.position.x + rect.size.x
	var bottom = rect.position.y + rect.size.y

	var pts = PackedVector2Array()
	pts.append_array(_arc(Vector2(left + tl,  top + tl),    tl, PI,       PI * 1.5, segments_per_corner))
	pts.append_array(_arc(Vector2(right - tr, top + tr),    tr, PI * 1.5, PI * 2.0, segments_per_corner))
	pts.append_array(_arc(Vector2(right - br, bottom - br), br, 0.0,      PI * 0.5, segments_per_corner))
	pts.append_array(_arc(Vector2(left + bl,  bottom - bl), bl, PI * 0.5, PI,       segments_per_corner))
	return pts

func _radii_clamped(size: Vector2) -> Dictionary:
	var w = size.x
	var h = size.y
	var tl = max(0.0, corner_radius_top_left)
	var tr = max(0.0, corner_radius_top_right)
	var br = max(0.0, corner_radius_bottom_right)
	var bl = max(0.0, corner_radius_bottom_left)

	var sum_h_top = tl + tr
	var sum_h_bot = bl + br
	var sum_v_left = tl + bl
	var sum_v_right = tr + br

	var scale_x = 1.0
	var scale_y = 1.0
	if sum_h_top > w:
		scale_x = min(scale_x, w / max(sum_h_top, 0.00001))
	if sum_h_bot > w:
		scale_x = min(scale_x, w / max(sum_h_bot, 0.00001))
	if sum_v_left > h:
		scale_y = min(scale_y, h / max(sum_v_left, 0.00001))
	if sum_v_right > h:
		scale_y = min(scale_y, h / max(sum_v_right, 0.00001))

	var s = min(scale_x, scale_y)
	tl *= s
	tr *= s
	br *= s
	bl *= s

	return { "tl": tl, "tr": tr, "br": br, "bl": bl }

func _radii_inset(r: Dictionary, inset: float, inner_size: Vector2) -> Dictionary:
	return {
		"tl": clamp(r.tl - inset, 0.0, min(inner_size.x, inner_size.y) * 0.5),
		"tr": clamp(r.tr - inset, 0.0, min(inner_size.x, inner_size.y) * 0.5),
		"br": clamp(r.br - inset, 0.0, min(inner_size.x, inner_size.y) * 0.5),
		"bl": clamp(r.bl - inset, 0.0, min(inner_size.x, inner_size.y) * 0.5),
	}
