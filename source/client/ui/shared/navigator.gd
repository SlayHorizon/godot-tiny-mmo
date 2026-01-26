class_name Navigator
extends Control


@export var initial_panel: NavPanel
@export var nav_panels: Array[NavPanel]

var current: NavPanel
var stack: Array[NavPanel]


func _ready() -> void:
	for panel: NavPanel in nav_panels:
		panel.navigate_requested.connect(_on_navigate_requested)
		panel.back_requested.connect(_on_back_requested)
		panel.hide()

	if initial_panel:
		reset(initial_panel, {})


func _on_navigate_requested(
	action: NavPanel.NavigationAction,
	target: NavPanel,
	payload: Dictionary
) -> void:
	match action:
		NavPanel.NavigationAction.PUSH:
			push(target, payload)
		NavPanel.NavigationAction.REPLACE:
			replace(target, payload)
		NavPanel.NavigationAction.RESET:
			reset(target, payload)


func _on_back_requested(payload: Dictionary) -> void:
	back(payload)


func push(target: NavPanel, payload: Dictionary) -> void:
	if current:
		hide_panel(current, payload)
		stack.append(current)
	show_panel(target, payload)


func replace(target: NavPanel, payload: Dictionary) -> void:
	if current:
		hide_panel(current, payload)
	show_panel(target, payload)


func reset(target: NavPanel, payload: Dictionary) -> void:
	if current:
		hide_panel(current, payload)
	stack.clear()
	show_panel(target, payload)


func back(payload: Dictionary = {}) -> void:
	if not current:
		return

	if stack.size():
		hide_panel(current, payload)
		current = stack.pop_back()
		current.enter(payload)
		current.show()
	else:
		hide()


func show_panel(panel: NavPanel, payload: Dictionary) -> void:
	current = panel 
	panel.show()
	panel.enter(payload)


func hide_panel(panel: NavPanel, payload: Dictionary) -> void:
	panel.exit(payload)
	panel.hide()
