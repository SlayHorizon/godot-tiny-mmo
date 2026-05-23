extends Control


var _shop_id: StringName
var _selected_slot: ShopSlot
var _golds: int
var _slots: Array[ShopSlot]
var _golds_label: Label

@onready var grid_container: GridContainer = $Panel/ScrollContainer/GridContainer
@onready var item_info: ColorRect = $ItemInfo
@onready var item_preview_icon: TextureRect = $ItemInfo/PanelContainer/VBoxContainer/ItemPreviewIcon
@onready var item_amount_label: Label = $ItemInfo/PanelContainer/VBoxContainer/ItemAmountLabel
@onready var item_description: RichTextLabel = $ItemInfo/PanelContainer/VBoxContainer/ItemDescription
@onready var back_button: Button = $ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/BackButton
@onready var buy_button: Button = $ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/BuyButton


func _ready() -> void:
	# Golds readout, centered just above the shop panel.
	_golds_label = Label.new()
	_golds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_golds_label)
	_golds_label.anchor_left = 0.5
	_golds_label.anchor_right = 0.5
	_golds_label.anchor_top = 0.5
	_golds_label.anchor_bottom = 0.5
	_golds_label.offset_left = -252.0
	_golds_label.offset_right = 252.0
	_golds_label.offset_top = -184.0
	_golds_label.offset_bottom = -158.0
	_set_golds(0)


func open(shop_id: StringName) -> void:
	# Re-fetch every open so golds and affordability reflect the latest state.
	_shop_id = shop_id
	_fetch_shop()


func _fetch_shop() -> void:
	for child in grid_container.get_children():
		child.queue_free()
	_slots.clear()

	var result: Array = await Client.request_data_await(&"shop.get", {"shop_id": _shop_id})
	if result[1] != OK:
		return

	var data: Dictionary = result[0]
	_set_golds(int(data.get("golds", 0)))

	var items: Array = data.get("items", [])
	for entry: Dictionary in items:
		var item_id: int = int(entry.get("id", 0))
		var price: int = int(entry.get("price", 0))
		if item_id <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		if not item:
			continue

		var item_button: Button = Button.new()
		item_button.custom_minimum_size = Vector2(80, 96)
		item_button.icon = item.item_icon
		item_button.expand_icon = true
		item_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		item_button.add_theme_constant_override(&"icon_max_width", 48)
		item_button.clip_text = true
		item_button.text = "%s\n%d g" % [item.item_name, price]
		grid_container.add_child(item_button)

		var slot: ShopSlot = ShopSlot.new()
		slot.button = item_button
		slot.item_id = item_id
		slot.item = item
		slot.price = price
		_slots.append(slot)
		item_button.pressed.connect(_on_item_slot_pressed.bind(slot))

	_refresh_affordability()


## Dim items the player can't afford (still clickable so they can be inspected).
func _refresh_affordability() -> void:
	for slot in _slots:
		slot.button.modulate = Color.WHITE if slot.price <= _golds else Color(1.0, 1.0, 1.0, 0.45)


func _set_golds(value: int) -> void:
	_golds = value
	if _golds_label:
		_golds_label.text = "Golds: %d" % _golds


func _on_close_button_pressed() -> void:
	hide()


func _on_item_slot_pressed(slot: ShopSlot) -> void:
	item_preview_icon.texture = slot.item.item_icon
	item_amount_label.text = "Price: %d golds" % slot.price
	item_description.text = slot.item.description
	_selected_slot = slot
	if not item_info.gui_input.is_connected(_on_item_info_gui_input):
		item_info.gui_input.connect(_on_item_info_gui_input)
	buy_button.disabled = slot.price > _golds
	item_info.show()


func _on_item_info_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_item_info()


func _close_item_info() -> void:
	if item_info.gui_input.is_connected(_on_item_info_gui_input):
		item_info.gui_input.disconnect(_on_item_info_gui_input)
	item_info.hide()


func _on_back_button_pressed() -> void:
	_close_item_info()


func _on_buy_button_pressed() -> void:
	buy_button.disabled = true
	back_button.disabled = true

	var result: Array = await Client.request_data_await(
		&"shop.buy.item",
		{"shop_id": _shop_id, "id": _selected_slot.item_id}
	)

	back_button.disabled = false

	if result[1] != OK:
		buy_button.disabled = false
		return

	var data: Dictionary = result[0]
	if not data.get("ok", false):
		item_amount_label.text = "Not enough golds! (Price: %d g)" % _selected_slot.price
		buy_button.disabled = false
		return

	_set_golds(int(data.get("golds", _golds)))
	_refresh_affordability()
	_close_item_info()


class ShopSlot:
	var button: Button
	var item_id: int
	var item: Item
	var price: int
