extends Control


## ALl items of the player inventory.
var inventory: Dictionary
## Filtered inventory showing equipment only.
var equipment_inventory: Dictionary
## Filtered inventory showing equipment only.
var materials_inventory: Dictionary

var latest_items: Dictionary


func _ready() -> void:
	pass


func fill_inventory(inventory: Dictionary) -> void:
	pass


func add_item() -> void:
	pass


func _on_close_button_pressed() -> void:
	hide()
