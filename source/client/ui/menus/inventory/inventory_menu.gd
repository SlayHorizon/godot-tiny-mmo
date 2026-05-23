extends Control


## All items of the player inventory, keyed by slot_uid.
var inventory: Dictionary[int, InventorySlot]
## Filtered inventory showing equipment only.
var equipment_inventory: Dictionary
## Filtered inventory showing equipment only.
var materials_inventory: Dictionary

var latest_items: Dictionary
var gear_slots_cache: Dictionary[Button, Item]
var selected_item: Item
var selected_slot: InventorySlot

@onready var inventory_grid: GridContainer = $MarginContainer/VBoxContainer/MainContainer/InventoryPanel/VBoxContainer/ScrollContainer/InventoryGrid
@onready var equipment_slots: GridContainer = $MarginContainer/VBoxContainer/MainContainer/CharacterPanel/VBoxContainer2/EquipmentSlots

@onready var item_info: ColorRect = $ItemInfo
@onready var item_preview_icon: TextureRect = $ItemInfo/PanelContainer/VBoxContainer/ItemPreviewIcon
@onready var item_amount_label: Label = $ItemInfo/PanelContainer/VBoxContainer/ItemAmountLabel
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
	fill_inventory()
	visibility_changed.connect(fill_inventory)


func fill_inventory() -> void:
	var request_result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if request_result[1] != OK:
		fill_inventory() 
		return

	var inventory_data: Dictionary = request_result[0]

	# Inventory is keyed by slot_uid; each slot holds {"id": item_id, "a": amount}.
	# Keys/numbers may arrive as strings/floats after JSON, so normalize with int().
	for slot_uid_key in inventory_data:
		var slot_uid: int = int(slot_uid_key)
		var slot_data: Dictionary = inventory_data[slot_uid_key]
		if not inventory.has(slot_uid):
			add_item(slot_uid, slot_data)
			continue
		inventory[slot_uid].update_slot(slot_data)


func add_item(slot_uid: int, slot_data: Dictionary) -> void:
	var item_id: int = int(slot_data.get("id", 0))
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
	var sb: StyleBox = Client.theme.get_stylebox(&"normal", &"Button")
	var content_margin: Vector2i = Vector2i(
		int(sb.get_content_margin(SIDE_LEFT)) + int(sb.get_content_margin(SIDE_RIGHT)),
		int(sb.get_content_margin(SIDE_TOP)) +  int(sb.get_content_margin(SIDE_BOTTOM)),
	)
	var available_size: Vector2i = Vector2i(new_button.custom_minimum_size) - content_margin
	var item_icon_size: Vector2i = item.item_icon.get_size()

	var final_size: Vector2i = (available_size - item_icon_size).snapped(item_icon_size)

	new_button.add_theme_constant_override(
			&"icon_max_width",
			final_size[final_size.min_axis_index()]
	)

	var quantity_label: Label = Label.new()
	quantity_label.text = "x%d" % int(slot_data.get("a", 1))
	quantity_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)

	new_button.add_child(quantity_label)

	new_button.icon = item.item_icon
	new_button.pressed.connect(
		_on_item_slot_button_pressed.bind(inventory_slot)
	)

	inventory_grid.add_child(new_button)

	inventory_slot.button = new_button
	inventory_slot.item_id = item_id
	inventory_slot.quantity = int(slot_data.get("a", 1))
	inventory_slot.item_data = slot_data
	inventory_slot.item = item
	inventory_slot.quantity_label = quantity_label

	inventory[slot_uid] = inventory_slot


func _on_close_button_pressed() -> void:
	hide()


func _on_item_slot_button_pressed(inventory_slot: InventorySlot) -> void:
	item_preview_icon.texture = inventory_slot.item.item_icon
	item_amount_label.text = "x%s" % inventory_slot.quantity
	item_description.text = inventory_slot.item.description
	
	if inventory_slot.item is GearItem:
		item_action_button.text = "Equip"
	elif inventory_slot.item is ConsumableItem:
		item_action_button.text = "Use"
	else:
		item_action_button.text = "Close"
	
	selected_item = inventory_slot.item
	selected_slot = inventory_slot

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
		var item_id: int = selected_slot.item_id if selected_slot else 0
		if item_id > 0:
			Client.request_data(
				&"item.equip",
				Callable(),
				{"id": item_id},
				InstanceClient.current.name
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
	var quantity_label: Label


	func update_slot(data: Dictionary) -> void:
		quantity = int(data.get("a", quantity))
		item_data.merge(data, true)
		if quantity_label:
			quantity_label.text = "x%d" % quantity


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
