extends Control


const STOCK_INFINITE_TEXT: String = "∞"

var _shop_id: int
var _selected_slot: ShopSlot
var _golds: int
var _slots: Array[ShopSlot]
## item_id -> amount the player owns. Fetched when the shop opens, kept in sync on buy.
var _owned: Dictionary[int, int]

@onready var shop_name_label: Label = %ShopNameLabel
@onready var golds_label: Label = %GoldsLabel
@onready var item_list: VBoxContainer = %ItemList
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name_label: Label = %DetailNameLabel
@onready var detail_price_label: Label = %DetailPriceLabel
@onready var detail_owned_label: Label = %DetailOwnedLabel
@onready var detail_description: RichTextLabel = %DetailDescription
@onready var buy_button: Button = %BuyButton


func open(shop_id: int) -> void:
	_shop_id = shop_id
	# Shop contents are static client-side data — render straight from the local
	# ShopResource. The server only authorizes + reports golds.
	var shop: ShopResource = ShopResource.load_shop(shop_id)
	if not shop:
		return
	if not shop.shop_name.is_empty():
		shop_name_label.text = shop.shop_name
	_build_list(shop)
	_clear_detail()
	_request_open()
	_request_inventory()


## Build the row list synchronously from local data (no await -> a double-emit open
## can't duplicate rows).
func _build_list(shop: ShopResource) -> void:
	for child in item_list.get_children():
		child.queue_free()
	_slots.clear()

	for entry: ShopEntry in shop.entries:
		if entry == null or entry.item == null:
			continue
		var slot: ShopSlot = ShopSlot.new()
		slot.item = entry.item
		slot.item_id = int(entry.item.get_meta(&"id", 0))
		slot.price = entry.price
		slot.button = _make_row(entry.item, entry.price)
		slot.button.pressed.connect(_on_row_pressed.bind(slot))
		item_list.add_child(slot.button)
		_slots.append(slot)

	_refresh_affordability()


func _make_row(item: Item, price: int) -> Button:
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
	hbox.add_child(_column(STOCK_INFINITE_TEXT, 64, HORIZONTAL_ALIGNMENT_CENTER))
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
	detail_price_label.text = "Price: %d golds" % slot.price
	detail_description.text = slot.item.description
	_update_owned_label()
	buy_button.disabled = slot.price > _golds


func _clear_detail() -> void:
	_selected_slot = null
	detail_icon.texture = null
	detail_name_label.text = "Select an item"
	detail_price_label.text = ""
	detail_owned_label.text = ""
	detail_description.text = ""
	buy_button.disabled = true


func _update_owned_label() -> void:
	if _selected_slot == null:
		detail_owned_label.text = ""
		return
	detail_owned_label.text = "In inventory: %d" % _owned.get(_selected_slot.item_id, 0)


## Dim rows the player can't afford (still clickable so they can be inspected).
func _refresh_affordability() -> void:
	for slot in _slots:
		slot.button.modulate = Color.WHITE if slot.price <= _golds else Color(1.0, 1.0, 1.0, 0.45)
	if _selected_slot:
		buy_button.disabled = _selected_slot.price > _golds


func _set_golds(value: int) -> void:
	_golds = value
	golds_label.text = "Golds: %d" % _golds


## Authorize opening + fetch current golds from the server.
func _request_open() -> void:
	var result: Array = await Client.request_data_await(&"shop.open", {"shop_id": _shop_id})
	if result[1] != OK:
		return
	var data: Dictionary = result[0]
	if not data.get("ok", false):
		hide()
		return
	_set_golds(int(data.get("golds", 0)))
	_refresh_affordability()


## Fetch the player's inventory so the detail panel can show owned counts.
func _request_inventory() -> void:
	var result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if result[1] != OK:
		return
	_owned.clear()
	var inventory: Dictionary = result[0]
	for slot_uid in inventory:
		var entry: Dictionary = inventory[slot_uid]
		var item_id: int = int(entry.get("id", 0))
		if item_id > 0:
			_owned[item_id] = _owned.get(item_id, 0) + int(entry.get("a", 0))
	_update_owned_label()


func _on_close_button_pressed() -> void:
	hide()


func _on_buy_button_pressed() -> void:
	if _selected_slot == null:
		return
	buy_button.disabled = true

	var result: Array = await Client.request_data_await(
		&"shop.buy.item",
		{"shop_id": _shop_id, "id": _selected_slot.item_id}
	)

	if result[1] != OK or not result[0].get("ok", false):
		buy_button.disabled = _selected_slot.price > _golds
		return

	_set_golds(int(result[0].get("golds", _golds)))
	_owned[_selected_slot.item_id] = _owned.get(_selected_slot.item_id, 0) + 1
	_update_owned_label()
	_refresh_affordability()


class ShopSlot:
	var button: Button
	var item: Item
	var item_id: int
	var price: int
