@tool
@icon("res://assets/node_icons/blue/icon_flag.png")
extends InteractionArea
class_name Teleporter
## Used to teleport from a point A to a point B inside the same instance.
## To change instance, use a Warper instead.

@export var one_way: bool = false
@export var target: Teleporter:
	set(value):
		# Needs rework.
		if value == target:
			return
		if value == null:
			if target:
				if not one_way:
					value = target
					target = null
					value.target = null
				target = null
		else:
			if value == self:
				value = null
				if target:
					if not one_way:
						target.target = null
					target = null
				push_warning("Impossible to assign a teleporter to itself.")
			target = value
			if target:
				if not one_way:
					target.target = self
		queue_redraw()
		update_configuration_warnings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if target:
			target.queue_redraw()
		queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	if target == null:
		return PackedStringArray([
			"This teleporter has no target!",
			"Consider adding one in the inspector tab."
		])
	return []


func _draw() -> void:
	if Engine.is_editor_hint():
		if target:
			draw_line(Vector2.ZERO, target.position-position,Color.RED, 1, true)
