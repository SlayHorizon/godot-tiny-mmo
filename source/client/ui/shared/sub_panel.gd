class_name SubPanel
extends PanelContainer


signal swap_requested(target: SubPanel, data: Dictionary, can_back: bool)
signal back_requested


func open(data: Dictionary) -> void:
	pass


func close() -> void:
	pass
