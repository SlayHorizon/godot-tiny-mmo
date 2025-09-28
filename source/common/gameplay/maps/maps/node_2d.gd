@tool
extends Node2D

@export var container_path: NodePath
@export var region: Rect2i
@export var fill_alpha: float = 0.07
@export var line_thickness: float = 2.0
@export var inside_color: Color
@export var outline_color: Color

var _cont: Node

func _ready() -> void:
	if Engine.is_editor_hint():
		_cont = get_node_or_null(container_path)
		queue_redraw()


func _process(_dt: float) -> void:
	if Engine.is_editor_hint():
		if _cont == null:
			_cont = get_node_or_null(container_path)
		queue_redraw()


func _draw() -> void:
	var cont := _cont as Node
	if cont == null: return
	#if not cont.has_method("get"): return
	# Access exported fields on the container
	#if not cont.has_method(&"get"): return
	#var show := cont.get("show_region_gizmo")
	#if not show: return
	var rect: Rect2 = region
	# Draw in Map-local space: place this gizmo under Map so coordinates match.
	draw_rect(rect, Color(0.1, 1.0, 0.3, fill_alpha), true)
	draw_rect(rect, Color(0.1, 1.0, 0.3, 0.9), false, line_thickness)
	# Optional: label
	var center := rect.position + rect.size * 0.5
	var label := "AOI " + str(cont.get("container_id"))
	draw_string(get_window().get_theme_default_font(), center + Vector2(6, -6), label)
