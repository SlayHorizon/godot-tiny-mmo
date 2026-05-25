extends Control
## Sandbox redesign of the character/inventory menu (kept separate from the live
## inventory_menu so it can be iterated/compared safely). Landscape layout:
## TopBar (title + wallet + close) / Body (equipment | stats+attributes | bag) /
## bottom DetailPanel that serves both bag items and equipped gear.

enum Category { ALL, GEAR, CONSUMABLES, MATERIALS }

var _inventory: Dictionary
var _gold_id: int
var _equipped_ids: Array
var _category: Category
var _filling: bool

## Current selection driving the DetailPanel.
var _selected_item: Item
var _selected_item_id: int
## Set when an equipped gear slot is selected (Unequip mode); empty for a bag item.
var _selected_gear_slot: StringName

@onready var title_label: Label = %TitleLabel
@onready var wallet_icon: TextureRect = %WalletIcon
@onready var wallet_amount: Label = %WalletAmount
@onready var equipment_slots: GridContainer = %EquipmentSlots
@onready var relic_slots: GridContainer = %RelicSlots
@onready var all_tab: Button = %AllTab
@onready var gear_tab: Button = %GearTab
@onready var consumables_tab: Button = %ConsumablesTab
@onready var materials_tab: Button = %MaterialsTab
@onready var inventory_grid: GridContainer = %InventoryGrid
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name: Label = %DetailName
@onready var detail_description: RichTextLabel = %DetailDescription
@onready var action_button: Button = %ActionButton


func _ready() -> void:
	_gold_id = Economy.gold_id()
	var gold: Item = ContentRegistryHub.load_by_id(&"items", _gold_id)
	if gold:
		wallet_icon.texture = gold.item_icon

	all_tab.pressed.connect(_set_category.bind(Category.ALL))
	gear_tab.pressed.connect(_set_category.bind(Category.GEAR))
	consumables_tab.pressed.connect(_set_category.bind(Category.CONSUMABLES))
	materials_tab.pressed.connect(_set_category.bind(Category.MATERIALS))

	for slot_button: GearSlotButton in _gear_buttons():
		slot_button.pressed.connect(_on_gear_slot_pressed.bind(slot_button))

	_connect_equipment_signal()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _connect_equipment_signal())

	_clear_detail()
	fill_inventory()
	visibility_changed.connect(fill_inventory)


func fill_inventory() -> void:
	if _filling:
		return
	_filling = true
	var result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	_filling = false
	if result[1] != OK:
		fill_inventory()
		return

	_inventory = result[0]
	_equipped_ids = _get_equipped_ids()
	_set_wallet(Inventory.count(_inventory, _gold_id))
	_rebuild_grid()
	_refresh_equipment_slots()


func _rebuild_grid() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()
	for slot_uid_key in _inventory:
		var data: Dictionary = _inventory[slot_uid_key]
		var item_id: int = int(data.get("id", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		if item == null or item.is_currency or not _passes_category(item):
			continue
		_add_bag_button(int(slot_uid_key), item_id, item, int(data.get("a", 1)))


func _passes_category(item: Item) -> bool:
	match _category:
		Category.GEAR:
			return item is GearItem or item is WeaponItem
		Category.CONSUMABLES:
			return item is ConsumableItem
		Category.MATERIALS:
			return not (item is GearItem or item is WeaponItem or item is ConsumableItem)
		_:
			return true


func _add_bag_button(_slot_uid: int, item_id: int, item: Item, quantity: int) -> void:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(64, 64)
	button.icon = item.item_icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	if quantity > 1:
		var qty: Label = Label.new()
		qty.text = "x%d" % quantity
		qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(qty)
	button.pressed.connect(_on_bag_item_pressed.bind(item_id, item))
	inventory_grid.add_child(button)


func _on_bag_item_pressed(item_id: int, item: Item) -> void:
	_selected_gear_slot = &""
	_selected_item = item
	_selected_item_id = item_id
	detail_icon.texture = item.item_icon
	detail_name.text = str(item.item_name)
	detail_description.text = item.description
	if item is GearItem or item is WeaponItem:
		action_button.text = "Equip"
		action_button.disabled = false
	elif item is ConsumableItem:
		action_button.text = "Use"
		action_button.disabled = false
	else:
		action_button.text = "—"
		action_button.disabled = true


func _on_gear_slot_pressed(slot_button: GearSlotButton) -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null or slot_button.gear_slot == null:
		return
	var key: StringName = slot_button.gear_slot.key
	var item_id: int = int(local_player.equipment_component.slots.values.get(key, 0))
	if item_id <= 0:
		return
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if item == null:
		return
	_selected_gear_slot = key
	_selected_item = item
	_selected_item_id = item_id
	detail_icon.texture = item.item_icon
	detail_name.text = str(item.item_name)
	detail_description.text = item.description
	action_button.text = "Unequip"
	action_button.disabled = false


func _clear_detail() -> void:
	_selected_item = null
	_selected_item_id = 0
	_selected_gear_slot = &""
	detail_icon.texture = null
	detail_name.text = "Select an item"
	detail_description.text = ""
	action_button.disabled = true


func _on_action_button_pressed() -> void:
	if not _selected_gear_slot.is_empty():
		var slot_key: StringName = _selected_gear_slot
		await Client.request_data_await(&"item.unequip", {"slot": slot_key}, InstanceClient.current.name)
		_clear_detail()
		fill_inventory()
		return
	if _selected_item_id > 0 and (_selected_item is GearItem or _selected_item is WeaponItem or _selected_item is ConsumableItem):
		await Client.request_data_await(&"item.equip", {"id": _selected_item_id}, InstanceClient.current.name)
		_clear_detail()
		fill_inventory()


func _set_category(category: Category) -> void:
	_category = category
	all_tab.disabled = category == Category.ALL
	gear_tab.disabled = category == Category.GEAR
	consumables_tab.disabled = category == Category.CONSUMABLES
	materials_tab.disabled = category == Category.MATERIALS
	_rebuild_grid()


func _set_wallet(amount: int) -> void:
	wallet_amount.text = str(amount)


func _on_close_button_pressed() -> void:
	hide()


# --- Equipment slot icons (reactive, like the live inventory) ---

func _connect_equipment_signal() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return
	if not local_player.equipment_component.equipment_changed.is_connected(_on_equipment_changed):
		local_player.equipment_component.equipment_changed.connect(_on_equipment_changed)
	_refresh_equipment_slots()


## All gear-slot buttons across the main equipment grid and the relic grid.
func _gear_buttons() -> Array:
	var out: Array
	for grid: Node in [equipment_slots, relic_slots]:
		for node: Node in grid.get_children():
			if node is GearSlotButton and node.gear_slot:
				out.append(node)
	return out


func _on_equipment_changed(slot_key: StringName, item_id: int) -> void:
	for gear_button: GearSlotButton in _gear_buttons():
		if gear_button.gear_slot.key == slot_key:
			_set_gear_icon(gear_button, item_id)


func _refresh_equipment_slots() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return
	for gear_button: GearSlotButton in _gear_buttons():
		_set_gear_icon(gear_button, int(local_player.equipment_component.slots.values.get(gear_button.gear_slot.key, 0)))


func _set_gear_icon(gear_button: GearSlotButton, item_id: int) -> void:
	if item_id > 0:
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		gear_button.icon = item.item_icon if item else gear_button.gear_slot.icon
	else:
		gear_button.icon = gear_button.gear_slot.icon


func _get_equipped_ids() -> Array:
	if ClientState.local_player == null:
		return []
	return ClientState.local_player.equipment_component.slots.values.values()
