extends Control


## ALl items of the player inventory.
var inventory: Dictionary[int, InventorySlot]
## Filtered inventory showing equipment only.
var equipment_inventory: Dictionary
## Filtered inventory showing equipment only.
var materials_inventory: Dictionary

var latest_items: Dictionary
var gear_slots_cache: Dictionary[Button, Item]
var selected_item: Item

@onready var inventory_grid: GridContainer = $MarginContainer/VBoxContainer/MainContainer/VBoxContainer2/InventoryPanel/VBoxContainer/ScrollContainer/InventoryGrid
@onready var equipment_slots: GridContainer = $MarginContainer/VBoxContainer/MainContainer/CharacterPanel/VBoxContainer2/EquipmentSlots

@onready var item_info: ColorRect = $ItemInfo
@onready var item_preview_icon: TextureRect = $ItemInfo/PanelContainer/VBoxContainer/ItemPreviewIcon
@onready var item_description: RichTextLabel = $ItemInfo/PanelContainer/VBoxContainer/ItemDescription
@onready var item_action_button: Button = $ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/ItemActionButton


func _ready() -> void:
	for equipment_slot: GearSlotButton in equipment_slots.get_children():
		if equipment_slot.gear_slot:
			if equipment_slot.gear_slot == null:
				equipment_slot.text = "Empty"
		else:
			equipment_slot.icon = null
			equipment_slot.text = "Lock"
	InstanceClient.current.request_data(&"inventory.get", fill_inventory)


func fill_inventory(inventory_data: Dictionary) -> void:
	print_debug(inventory_data)
	for item_id: int in inventory_data:
		var item_data: Dictionary = inventory_data[item_id]
		#if item_data.has("init"):
			#add_item(item_id, item_data)
			#continue
		if not inventory.has(item_id):
			add_item(item_id, item_data)
			# Error case ?
			continue
		inventory[item_id].update_slot(item_data)


func add_item(item_id: int, item_data: Dictionary) -> void:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if not item:
		return
	
	var inventory_slot: InventorySlot = InventorySlot.new()
	
	var new_button: Button = Button.new()
	new_button.custom_minimum_size = Vector2(60, 60)
	new_button.pressed.connect(
		_on_item_slot_button_pressed.bind(inventory_slot)
	)
	inventory_grid.add_child(new_button)
	
	inventory_slot.button = new_button
	inventory_slot.item_id = item_id
	inventory_slot.quantity = item_data.get("qty", 1)
	inventory_slot.item_data = item_data
	inventory_slot.item = item
	
	inventory[item_id] = inventory_slot


func _on_close_button_pressed() -> void:
	hide()


func _on_item_slot_button_pressed(inventory_slot: InventorySlot) -> void:
	item_preview_icon.texture = inventory_slot.item.item_icon
	item_description.text = inventory_slot.item.description
	
	if inventory_slot.item is GearItem:
		item_action_button.text = "Equip"
	else:
		item_action_button.text = "Close"
	
	selected_item = inventory_slot.item
	
	item_info.show()


func _on_item_action_button_pressed() -> void:
	if selected_item is GearItem or selected_item is WeaponItem:
		var item_id: int = selected_item.get_meta(&"id", -1)
		if item_id != -1:
			InstanceClient.current.request_data(
				&"item.equip",
				Callable(),
				{"id": item_id}
			)
	item_info.hide()


func _on_equip_button_pressed() -> void:
	if selected_item is GearItem or selected_item is WeaponItem:
		var item_id: int = selected_item.get_meta(&"id", -1)
		if item_id != -1:
			InstanceClient.current.request_data(
				&"item.equip",
				Callable(),
				{"id": item_id}
			)


class InventorySlot:
	var button: Button
	var quantity: int
	var item_id: int
	var item_data: Dictionary
	var item: Item


	func update_slot(data: Dictionary) -> void:
		quantity += data.get("add", 0)
		item_data.merge(data, true)
		button.text = str(quantity)
