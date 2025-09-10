extends Control


## ALl items of the player inventory.
var inventory: Dictionary
## Filtered inventory showing equipment only.
var equipment_inventory: Dictionary
## Filtered inventory showing equipment only.
var materials_inventory: Dictionary

var latest_items: Dictionary
var gear_slots_cache: Dictionary[Button, Item]

@onready var inventory_grid: GridContainer = $EquipmentView/HBoxContainer/VBoxContainer/InventoryGrid
@onready var equipment_slots: GridContainer = $EquipmentView/HBoxContainer/VBoxContainer2/EquipmentSlots


func _ready() -> void:
	InstanceClient.current.request_data(&"inventory", fill_inventory)


func fill_inventory(inventory: Dictionary) -> void:
	var slot_index: int = 0
	for item_id: int in inventory:
		var item: Item = ContentRegistryHub.load_by_id(&"gears", item_id)
		inventory.merge(inventory, true)
		if item:
			var button: Button = inventory_grid.get_child(slot_index) as Button
			button.icon = item.item_icon
			button.text = str(item_id)
			slot_index += 1
			gear_slots_cache.set(button, item)
			if not button.pressed.has_connections():
				button.pressed.connect(_on_item_slot_button_pressed.bind(button, item))
		print(item)
	for equipment_slot: GearSlotButton in equipment_slots.get_children():
		if equipment_slot.gear_slot:
			pass
		else:
			equipment_slot.icon = null
			equipment_slot.text = "Empty"


func add_item() -> void:
	pass


func _on_close_button_pressed() -> void:
	hide()


func _on_item_slot_button_pressed(button: Button, item: Item) -> void:
	pass
