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

@onready var shop_name_label: Label = %ShopNameLabel
@onready var golds_label: Label = %GoldsLabel
@onready var buy_tab: Button = %BuyTab
@onready var sell_tab: Button = %SellTab
@onready var item_list: VBoxContainer = %ItemList
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name_label: Label = %DetailNameLabel
@onready var detail_price_label: Label = %DetailPriceLabel
@onready var detail_owned_label: Label = %DetailOwnedLabel
@onready var detail_description: RichTextLabel = %DetailDescription
@onready var action_button: Button = %ActionButton


func _ready() -> void:
	# Active tab is the disabled one; clicking the other switches mode.
	buy_tab.pressed.connect(_set_mode.bind(Mode.BUY))
	sell_tab.pressed.connect(_set_mode.bind(Mode.SELL))


func open(shop_id: int) -> void:
	_shop_id = shop_id
	# Shop contents are static client-side data — render from the local ShopResource.
	_shop = ShopResource.load_shop(shop_id)
	if not _shop:
		return
	if not _shop.shop_name.is_empty():
		shop_name_label.text = _shop.shop_name
	sell_tab.visible = _shop.buys_from_players
	_set_mode(Mode.BUY)
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
		_build_sell_rows()

	_refresh_affordability()


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
	if _mode == Mode.BUY:
		detail_price_label.text = "Price: %d golds" % slot.price
		action_button.text = "Buy"
		action_button.disabled = slot.price > _golds
	else:
		detail_price_label.text = "Sells for: %d golds" % slot.price
		action_button.text = "Sell"
		action_button.disabled = false
	_update_owned_label()


func _clear_detail() -> void:
	_selected_slot = null
	detail_icon.texture = null
	detail_name_label.text = "Select an item"
	detail_price_label.text = ""
	detail_owned_label.text = ""
	detail_description.text = ""
	action_button.text = "Sell" if _mode == Mode.SELL else "Buy"
	action_button.disabled = true


func _update_owned_label() -> void:
	if _selected_slot == null:
		detail_owned_label.text = ""
		return
	var owned: int = _selected_slot.quantity if _mode == Mode.SELL else _owned.get(_selected_slot.item_id, 0)
	detail_owned_label.text = "In inventory: %d" % owned


## Dim unaffordable rows in Buy mode (still clickable). No dimming in Sell mode.
func _refresh_affordability() -> void:
	for slot in _slots:
		if _mode == Mode.BUY:
			slot.button.modulate = Color.WHITE if slot.price <= _golds else Color(1.0, 1.0, 1.0, 0.45)
		else:
			slot.button.modulate = Color.WHITE
	if _selected_slot and _mode == Mode.BUY:
		action_button.disabled = _selected_slot.price > _golds


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
	action_button.disabled = true
	var result: Array = await Client.request_data_await(
		&"shop.buy.item",
		{"shop_id": _shop_id, "id": _selected_slot.item_id}
	)
	if result[1] != OK or not result[0].get("ok", false):
		if _selected_slot:
			action_button.disabled = _selected_slot.price > _golds
		return
	_set_golds(int(result[0].get("golds", _golds)))
	_refresh_affordability()
	await _request_inventory()


func _sell() -> void:
	var slot_uid: int = _selected_slot.slot_uid
	action_button.disabled = true
	var result: Array = await Client.request_data_await(
		&"shop.sell.item",
		{"shop_id": _shop_id, "slot_uid": slot_uid, "amount": 1}
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
