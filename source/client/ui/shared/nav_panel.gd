class_name NavPanel
extends PanelContainer


enum NavigationAction {
	PUSH,
	REPLACE,
	RESET,
}

signal navigate_requested(action: NavigationAction, target: StringName, payload: Dictionary)
signal back_requested(payload: Dictionary)


func enter(payload: Dictionary = {}) -> void:
	pass


func exit(payload: Dictionary = {}) -> void:
	pass
