extends MenuShell
## Character / inventory menu. Built on the shared [MenuShell]: title + wallet
## + close live in the banner header; the body (equipment | bag) and the bottom
## detail strip are wrapped in the card. The detail strip serves both bag items
## and equipped gear.

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

## Wallet widgets, created in the shell header at runtime.
var wallet_icon: TextureRect
var wallet_amount: Label
## "Hotkey" button in the detail strip (created next to ActionButton at
## runtime) — assigns the selected bag item to a HUD quick slot.
var hotkey_button: Button
## Crisp pixel preview mounted onto %DetailIcon (used as a sizing host; its own texture stays null).
var _detail_pixel: TextureRect
@onready var equipment_slots: GridContainer = %EquipmentSlots
@onready var relic_slots: GridContainer = %RelicSlots
@onready var all_tab: Button = %AllTab
@onready var gear_tab: Button = %GearTab
@onready var consumables_tab: Button = %ConsumablesTab
@onready var materials_tab: Button = %MaterialsTab
@onready var inventory_grid: GridContainer = %InventoryGrid
@onready var inventory_scroll: ScrollContainer = $MainBody/Body/BagPanel/MarginContainer/VBoxContainer/ScrollContainer
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name: Label = %DetailName
@onready var detail_description: RichTextLabel = %DetailDescription
@onready var action_button: Button = %ActionButton


func _ready() -> void:
	_gold_id = Economy.gold_id()
	# Wrap the authored body in the shared menu shell (banner header + card).
	build_shell("Inventory", $MainBody, true)
	_build_wallet()
	detail_icon.texture = null  # %DetailIcon is now just a sizing host for the crisp pixel preview
	_detail_pixel = PixelIcon.mount(detail_icon)

	all_tab.pressed.connect(_set_category.bind(Category.ALL))
	gear_tab.pressed.connect(_set_category.bind(Category.GEAR))
	consumables_tab.pressed.connect(_set_category.bind(Category.CONSUMABLES))
	materials_tab.pressed.connect(_set_category.bind(Category.MATERIALS))

	for slot_button: GearSlotButton in _gear_buttons():
		slot_button.pressed.connect(_on_gear_slot_pressed.bind(slot_button))

	hotkey_button = Button.new()
	hotkey_button.text = "Hotkey"
	# Twin of ActionButton — same size and centering, consistent tap target.
	hotkey_button.custom_minimum_size = action_button.custom_minimum_size
	hotkey_button.size_flags_vertical = action_button.size_flags_vertical
	hotkey_button.disabled = true
	hotkey_button.pressed.connect(_on_hotkey_button_pressed)
	action_button.add_sibling(hotkey_button)

	_connect_equipment_signal()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _connect_equipment_signal())

	_clear_detail()
	fill_inventory()
	visibility_changed.connect(fill_inventory)
	# Refresh the bag live when ore is gathered while the menu is open.
	ClientState.gather_succeeded.connect(func(_result: Dictionary):
		if visible:
			fill_inventory())


## Currency chip (icon + amount) in the shell header, top-right next to Close.
## Icon-driven so it's ready for alt-currency the same way the shop is.
func _build_wallet() -> void:
	wallet_icon = TextureRect.new()
	wallet_icon.custom_minimum_size = Vector2(22, 22)
	wallet_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	wallet_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var gold: Item = ContentRegistryHub.load_by_id(&"items", _gold_id)
	if gold:
		wallet_icon.texture = gold.item_icon
	wallet_amount = Label.new()
	wallet_amount.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	wallet_amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_right.add_child(wallet_icon)
	header_right.add_child(wallet_amount)
	header_right.move_child(wallet_icon, 0)
	header_right.move_child(wallet_amount, 1)


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
	DragScroll.enable(inventory_scroll) # touch/mouse drag-scroll the bag (flips fresh rows to PASS)


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
	button.clip_contents = true
	PixelIcon.mount(button, item.item_icon)
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
	PixelIcon.set_art(_detail_pixel, item.item_icon)
	detail_name.text = str(item.item_name)
	detail_description.bbcode_enabled = true
	detail_description.text = ItemTooltip.body(item)
	if item is GearItem or item is WeaponItem:
		action_button.text = "Equip"
		action_button.disabled = false
	elif item is ConsumableItem:
		action_button.text = "Use"
		action_button.disabled = false
	elif item.holdable:
		action_button.text = "Hold"
		action_button.disabled = false
	else:
		action_button.text = "—"
		action_button.disabled = true
	# Anything you can equip / use / hold can sit on a quick slot.
	hotkey_button.disabled = action_button.disabled


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
	PixelIcon.set_art(_detail_pixel, item.item_icon)
	detail_name.text = str(item.item_name)
	detail_description.bbcode_enabled = true
	detail_description.text = ItemTooltip.body(item)
	action_button.text = "Unequip"
	action_button.disabled = false
	hotkey_button.disabled = true # bag items only — equipped gear isn't in the bag


func _clear_detail() -> void:
	_selected_item = null
	_selected_item_id = 0
	_selected_gear_slot = &""
	PixelIcon.set_art(_detail_pixel, null)
	detail_name.text = "Select an item"
	detail_description.text = ""
	action_button.disabled = true
	if hotkey_button != null:
		hotkey_button.disabled = true


## Opens the shared slot picker for the selected bag item. Picking the slot
## the item already occupies clears it (toggle); picking another slot moves
## it there, vacating its old one.
func _on_hotkey_button_pressed() -> void:
	if _selected_item == null:
		return
	var item: Item = _selected_item
	var entries: PackedStringArray = PackedStringArray()
	for i: int in 3:
		var occupant: Item = ClientState.quick_slots.get_key(i) as Item
		var occupant_name: String = String(occupant.item_name) if occupant != null else "empty"
		entries.append("Slot %d (key %d)  —  %s" % [i + 1, i + 1, occupant_name])
	SlotPickerOverlay.open(self, "Place %s on which quick slot?" % item.item_name, entries,
		func(slot: int) -> void:
			var occupant: Item = ClientState.quick_slots.get_key(slot) as Item
			if occupant == item:
				ClientState.quick_slots.set_key(slot, null) # toggle off
				return
			# Move semantics: vacate any other slot already holding this item.
			for i: int in 3:
				if (ClientState.quick_slots.get_key(i) as Item) == item:
					ClientState.quick_slots.set_key(i, null)
			ClientState.quick_slots.set_key(slot, item)
	)


func _on_action_button_pressed() -> void:
	if not _selected_gear_slot.is_empty():
		var slot_key: StringName = _selected_gear_slot
		var unequip_result: Array = await Client.request_data_await(&"item.unequip", {"slot": slot_key}, InstanceClient.current.name)
		if not _surface_item_rejection(unequip_result):
			_clear_detail()
			fill_inventory()
		return
	if _selected_item_id > 0 and (_selected_item is GearItem or _selected_item is WeaponItem or _selected_item.holdable):
		var result: Array = await Client.request_data_await(&"item.equip", {"id": _selected_item_id}, InstanceClient.current.name)
		if not _surface_item_rejection(result):
			_clear_detail()
			fill_inventory()


## Toasts a server rejection (combat lock, cooldown) and returns true if the
## action was rejected, so the caller skips the success refresh.
func _surface_item_rejection(result: Array) -> bool:
	var payload: Dictionary = result[0] if result[1] == OK and result[0] is Dictionary else {}
	match str(payload.get("reason", "")):
		"in_combat":
			Toaster.toast("Can't change gear in combat (weapons only).")
			return true
		"cooldown":
			Toaster.toast("That's still on cooldown.")
			return true
		"level":
			Toaster.toast("Requires level %d to equip." % int(payload.get("level", 0)))
			return true
		"cant_equip":
			Toaster.toast("You can't equip that.")
			return true
	return false


func _set_category(category: Category) -> void:
	_category = category
	all_tab.button_pressed = category == Category.ALL
	gear_tab.button_pressed = category == Category.GEAR
	consumables_tab.button_pressed = category == Category.CONSUMABLES
	materials_tab.button_pressed = category == Category.MATERIALS
	_rebuild_grid()


func _set_wallet(amount: int) -> void:
	wallet_amount.text = str(amount)


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
		gear_button.set_item_icon(item.item_icon if item else gear_button.gear_slot.icon)
	else:
		gear_button.set_item_icon(gear_button.gear_slot.icon)


func _get_equipped_ids() -> Array:
	if ClientState.local_player == null:
		return []
	return ClientState.local_player.equipment_component.slots.values.values()
