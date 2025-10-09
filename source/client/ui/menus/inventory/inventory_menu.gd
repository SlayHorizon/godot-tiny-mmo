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

@onready var inventory_grid: GridContainer = $MarginContainer/VBoxContainer/MainContainer/InventoryPanel/VBoxContainer/ScrollContainer/InventoryGrid
@onready var equipment_slots: GridContainer = $MarginContainer/VBoxContainer/MainContainer/CharacterPanel/VBoxContainer2/EquipmentSlots

@onready var item_info: ColorRect = $ItemInfo
@onready var item_preview_icon: TextureRect = $ItemInfo/PanelContainer/VBoxContainer/ItemPreviewIcon
@onready var item_description: RichTextLabel = $ItemInfo/PanelContainer/VBoxContainer/ItemDescription
@onready var item_action_button: Button = $ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/ItemActionButton
@onready var quick_slots_container: HBoxContainer = $ItemInfo/HotkeyPanel/VBoxContainer/HBoxContainer


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
	for item_id: int in inventory_data:
		var item_data: Dictionary = inventory_data[item_id]
		if not inventory.has(item_id):
			add_item(item_id, item_data)
			continue
		inventory[item_id].update_slot(item_data)


func add_item(item_id: int, item_data: Dictionary) -> void:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if not item:
		return
	
	var inventory_slot: InventorySlot = InventorySlot.new()
	
	var new_button: Button = Button.new()
	
	new_button.custom_minimum_size = Vector2(62, 62)
	
	new_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_button.expand_icon = true
	
	# Calcul the should be size of the icon
	# If we don't want to have blrurry pixel art
	var sb: StyleBox = BetterThemeDB.theme.get_stylebox(&"normal", &"Button")
	var content_margin: Vector2i = Vector2i(
		sb.get_content_margin(SIDE_LEFT) + sb.get_content_margin(SIDE_RIGHT),
		sb.get_content_margin(SIDE_TOP) +  sb.get_content_margin(SIDE_BOTTOM),
	)
	var available_size: Vector2i = Vector2i(new_button.custom_minimum_size) - content_margin
	var item_icon_size: Vector2i = item.item_icon.get_size()

	var final_size: Vector2i = (available_size - item_icon_size).snapped(item_icon_size)
	
	new_button.add_theme_constant_override(
			&"icon_max_width",
			final_size[final_size.min_axis_index()]
			)
	
	new_button.icon = item.item_icon
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
	elif inventory_slot.item is ConsumableItem:
		item_action_button.text = "Use"
	else:
		item_action_button.text = "Close"
	
	selected_item = inventory_slot.item
	
	item_info.gui_input.connect(_on_item_info_gui_input)
	
	if selected_item is WeaponItem or selected_item is ConsumableItem:
		$ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/HotkeyButton.show()
	else:
		$ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/HotkeyButton.hide()
	item_info.show()


func _on_item_info_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		item_info.gui_input.disconnect(_on_item_info_gui_input)
		$ItemInfo/HotkeyPanel.hide()
		item_info.hide()


func _on_item_action_button_pressed() -> void:
	if selected_item is GearItem or selected_item is WeaponItem:
		var item_id: int = selected_item.get_meta(&"id", -1)
		if item_id != -1:
			InstanceClient.current.request_data(
				&"item.equip",
				Callable(),
				{"id": item_id}
			)
			for equipment_slot: GearSlotButton in equipment_slots.get_children():
				if selected_item.slot == equipment_slot.gear_slot:
					equipment_slot.icon = selected_item.item_icon
	item_info.gui_input.disconnect(_on_item_info_gui_input)
	item_info.hide()


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

var connect_hotkey_once: bool = false
func _on_hotkey_button_pressed() -> void:
	var hotkey_index: int = 0
	
	for button: Button in quick_slots_container.get_children():
		if ClientState.quick_slots.data.has(hotkey_index):
			button.icon = (ClientState.quick_slots.get_key(hotkey_index, null) as Item).item_icon
			button.text = ""
		if not connect_hotkey_once:
			if hotkey_index < 2:
				button.pressed.connect(_on_hotkey_index_pressed.bind(hotkey_index))
			else:
				button.text = "Lock"
		hotkey_index += 1
	connect_hotkey_once = true
	$ItemInfo/HotkeyPanel.show()


func _on_hotkey_index_pressed(hotkey_index: int) -> void:
	ClientState.quick_slots.set_key(hotkey_index, selected_item)
	
	var button: Button = quick_slots_container.get_child(hotkey_index)
	button.icon = selected_item.item_icon
	$ItemInfo/HotkeyPanel.hide()


func _on_hotkey_cancel_button_pressed() -> void:
	$ItemInfo/HotkeyPanel.hide()
