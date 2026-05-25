extends Control


enum Mode { BUY, SELL }

const STOCK_INFINITE_TEXT: String = "∞"

var _shop: ShopResource
var _shop_id: int
var _mode: Mode
var _golds: int
var _slots: Array[ShopSlot]
var _selected_slot: ShopSlot
## Raw inventory (slot_uid -> {"id", "a"}), fetched on open and after each transaction.
var _inventory: Dictionary
## item_id -> total owned, derived from _inventory (for the Buy-mode owned count).
var _owned: Dictionary[int, int]
## item_ids the local player currently has equipped (can't be sold). Refreshed per list build.
var _equipped_ids: Array

@onready var shop_name_label: Label = %ShopNameLabel
@onready var golds_label: Label = %GoldsLabel
@onready var mode_tabs: HBoxContainer = %ModeTabs
@onready var buy_tab: Button = %BuyTab
@onready var sell_tab: Button = %SellTab
@onready var item_list: VBoxContainer = %ItemList
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name_label: Label = %DetailNameLabel
@onready var detail_price_label: Label = %DetailPriceLabel
@onready var detail_owned_label: Label = %DetailOwnedLabel
@onready var detail_description: RichTextLabel = %DetailDescription
@onready var quantity_row: HBoxContainer = %QuantityRow
@onready var quantity_spinbox: SpinBox = %QuantitySpinBox
@onready var max_button: Button = %MaxButton
@onready var action_button: Button = %ActionButton


func _ready() -> void:
	# Active tab is the disabled one; clicking the other switches mode.
	buy_tab.pressed.connect(_set_mode.bind(Mode.BUY))
	sell_tab.pressed.connect(_set_mode.bind(Mode.SELL))
	quantity_spinbox.value_changed.connect(_on_quantity_changed)
	max_button.pressed.connect(func(): quantity_spinbox.value = quantity_spinbox.max_value)


func open(shop_id: int) -> void:
	_shop_id = shop_id
	# Shop contents are static client-side data — render from the local ShopResource.
	_shop = ShopResource.load_shop(shop_id)
	if not _shop:
		return
	if not _shop.shop_name.is_empty():
		shop_name_label.text = _shop.shop_name
	# Only show the tab bar when the shop offers both; otherwise go straight to the
	# single relevant interface.
	mode_tabs.visible = _shop.trades == ShopResource.Trades.BOTH
	_set_mode(Mode.SELL if _shop.trades == ShopResource.Trades.SELL_ONLY else Mode.BUY)
	# Dynamic/authoritative bits from the server.
	_request_open()
	_request_inventory()


func _set_mode(mode: Mode) -> void:
	_mode = mode
	buy_tab.disabled = mode == Mode.BUY
	sell_tab.disabled = mode == Mode.SELL
	_build_list()
	_clear_detail()


## Build the row list synchronously (no await -> double-emit can't duplicate rows).
func _build_list() -> void:
	for child in item_list.get_children():
		child.queue_free()
	_slots.clear()

	if _mode == Mode.BUY:
		_build_buy_rows()
	else:
		_equipped_ids = _get_equipped_ids()
		_build_sell_rows()

	_refresh_affordability()


## item_ids the local player has equipped (can't be sold while worn).
func _get_equipped_ids() -> Array:
	if ClientState.local_player == null:
		return []
	return ClientState.local_player.equipment_component.slots.values.values()


func _build_buy_rows() -> void:
	for entry: ShopEntry in _shop.entries:
		if entry == null or entry.item == null:
			continue
		var slot: ShopSlot = ShopSlot.new()
		slot.item = entry.item
		slot.item_id = int(entry.item.get_meta(&"id", 0))
		slot.price = entry.price
		_add_row(slot, STOCK_INFINITE_TEXT)


func _build_sell_rows() -> void:
	for slot_uid in _inventory:
		var data: Dictionary = _inventory[slot_uid]
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(data.get("id", 0)))
		if item == null or item.vendor_value <= 0:
			continue # not sellable to vendors
		var slot: ShopSlot = ShopSlot.new()
		slot.item = item
		slot.item_id = int(data.get("id", 0))
		slot.price = item.vendor_value
		slot.slot_uid = int(slot_uid)
		slot.quantity = int(data.get("a", 0))
		_add_row(slot, str(slot.quantity))


func _add_row(slot: ShopSlot, middle_text: String) -> void:
	slot.button = _make_row(slot.item, middle_text, slot.price)
	slot.button.pressed.connect(_on_row_pressed.bind(slot))
	item_list.add_child(slot.button)
	_slots.append(slot)


func _make_row(item: Item, middle_text: String, price: int) -> Button:
	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, 64)
	row.focus_mode = Control.FOCUS_ALL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override(&"separation", 8)
	row.add_child(hbox)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.texture = item.item_icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	hbox.add_child(_column(str(item.item_name), 0, HORIZONTAL_ALIGNMENT_LEFT))
	hbox.add_child(_column(middle_text, 64, HORIZONTAL_ALIGNMENT_CENTER))
	hbox.add_child(_column("%d g" % price, 88, HORIZONTAL_ALIGNMENT_CENTER))

	return row


## A label column. width 0 means "expand to fill".
func _column(text: String, width: int, align: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0:
		label.custom_minimum_size = Vector2(width, 0)
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _on_row_pressed(slot: ShopSlot) -> void:
	_selected_slot = slot
	detail_icon.texture = slot.item.item_icon
	detail_name_label.text = str(slot.item.item_name)
	detail_description.text = slot.item.description
	quantity_row.visible = true
	quantity_spinbox.set_value_no_signal(1)
	_update_quantity_bounds()
	_update_price_label()
	_update_owned_label()
	if _mode == Mode.SELL:
		if slot.item_id in _equipped_ids:
			action_button.text = "Equipped"
			action_button.disabled = true
		else:
			action_button.text = "Sell"
			action_button.disabled = false
	else:
		action_button.text = "Buy"
		_refresh_buy_action()


func _clear_detail() -> void:
	_selected_slot = null
	detail_icon.texture = null
	detail_name_label.text = "Select an item"
	detail_price_label.text = ""
	detail_owned_label.text = ""
	detail_description.text = ""
	quantity_row.visible = false
	action_button.text = "Sell" if _mode == Mode.SELL else "Buy"
	action_button.disabled = true


## Cap the quantity spinbox at what's affordable (buy) / owned (sell).
func _update_quantity_bounds() -> void:
	if _selected_slot == null:
		return
	var max_qty: int = (
		maxi(1, _selected_slot.quantity) if _mode == Mode.SELL
		else maxi(1, _affordable_count(_selected_slot.price))
	)
	quantity_spinbox.max_value = max_qty
	if int(quantity_spinbox.value) > max_qty:
		quantity_spinbox.set_value_no_signal(max_qty)


func _affordable_count(price: int) -> int:
	if price <= 0:
		return 999
	return floori(_golds / float(price))


func _update_price_label() -> void:
	if _selected_slot == null:
		detail_price_label.text = ""
		return
	var total: int = _selected_slot.price * int(quantity_spinbox.value)
	detail_price_label.text = (
		"Sells for: %d golds" % total if _mode == Mode.SELL
		else "Price: %d golds" % total
	)


func _update_owned_label() -> void:
	if _selected_slot == null:
		detail_owned_label.text = ""
		return
	var owned: int = _selected_slot.quantity if _mode == Mode.SELL else _owned.get(_selected_slot.item_id, 0)
	detail_owned_label.text = "In inventory: %d" % owned


## In Buy mode, enable/disable the action by whether the chosen quantity is affordable.
func _refresh_buy_action() -> void:
	if _selected_slot and _mode == Mode.BUY:
		action_button.disabled = _selected_slot.price * int(quantity_spinbox.value) > _golds


func _on_quantity_changed(_value: float) -> void:
	_update_price_label()
	_refresh_buy_action()


## Dim unaffordable rows in Buy mode (still clickable). No dimming in Sell mode.
func _refresh_affordability() -> void:
	for slot in _slots:
		if _mode == Mode.BUY:
			slot.button.modulate = Color.WHITE if slot.price <= _golds else Color(1.0, 1.0, 1.0, 0.45)
		else:
			# Dim equipped items in the Sell list (can't be sold while worn).
			slot.button.modulate = Color(1.0, 1.0, 1.0, 0.45) if slot.item_id in _equipped_ids else Color.WHITE


func _set_golds(value: int) -> void:
	_golds = value
	golds_label.text = "Golds: %d" % _golds


## Authorize opening + fetch current golds.
func _request_open() -> void:
	var result: Array = await Client.request_data_await(&"shop.open", {"shop_id": _shop_id})
	if result[1] != OK:
		return
	if not result[0].get("ok", false):
		hide()
		return
	_set_golds(int(result[0].get("golds", 0)))
	_refresh_affordability()
	if _selected_slot and _mode == Mode.BUY:
		_update_quantity_bounds()
		_refresh_buy_action()


## Refresh the player's inventory (owned counts + the Sell list).
func _request_inventory() -> void:
	var result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if result[1] != OK:
		return
	_inventory = result[0]
	_recompute_owned()
	if _mode == Mode.SELL:
		_build_list()
	_update_owned_label()


func _recompute_owned() -> void:
	_owned.clear()
	for slot_uid in _inventory:
		var data: Dictionary = _inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		if item_id > 0:
			_owned[item_id] = _owned.get(item_id, 0) + int(data.get("a", 0))


func _on_close_button_pressed() -> void:
	hide()


func _on_action_button_pressed() -> void:
	if _selected_slot == null:
		return
	if _mode == Mode.BUY:
		_buy()
	else:
		_sell()


func _buy() -> void:
	var amount: int = int(quantity_spinbox.value)
	action_button.disabled = true
	var result: Array = await Client.request_data_await(
		&"shop.buy.item",
		{"shop_id": _shop_id, "id": _selected_slot.item_id, "amount": amount}
	)
	if result[1] != OK or not result[0].get("ok", false):
		_refresh_buy_action()
		return
	_set_golds(int(result[0].get("golds", _golds)))
	_refresh_affordability()
	await _request_inventory()
	if _selected_slot:
		_update_quantity_bounds()
		_update_price_label()
		_refresh_buy_action()


func _sell() -> void:
	var slot_uid: int = _selected_slot.slot_uid
	var amount: int = int(quantity_spinbox.value)
	action_button.disabled = true
	var result: Array = await Client.request_data_await(
		&"shop.sell.item",
		{"shop_id": _shop_id, "slot_uid": slot_uid, "amount": amount}
	)
	if result[1] != OK or not result[0].get("ok", false):
		action_button.disabled = false
		return
	_set_golds(int(result[0].get("golds", _golds)))
	await _request_inventory() # rebuilds the Sell list with updated quantities
	# Keep the same item selected if its stack still exists.
	for slot in _slots:
		if slot.slot_uid == slot_uid:
			_on_row_pressed(slot)
			return
	_clear_detail()


class ShopSlot:
	var button: Button
	var item: Item
	var item_id: int
	var price: int
	## Sell mode only:
	var slot_uid: int
	var quantity: int
