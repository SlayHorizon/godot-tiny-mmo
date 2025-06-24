class_name MouseComponent
extends Node2D


var mouse_ingame: bool = true
var window_focus: bool = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_ENTER:
		mouse_ingame = true
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		mouse_ingame = false
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		window_focus = true
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		window_focus = false


func _process(_delta: float) -> void:
	if mouse_ingame and window_focus:
		position = get_global_mouse_position()
