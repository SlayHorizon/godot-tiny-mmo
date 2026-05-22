extends Control


var _shop_id: StringName = &""
var _selected_slot: ShopSlot

@onready var grid_container: GridContainer = $Panel/ScrollContainer/GridContainer
@onready var item_info: ColorRect = $ItemInfo
@onready var item_preview_icon: TextureRect = $ItemInfo/PanelContainer/VBoxContainer/ItemPreviewIcon
@onready var item_amount_label: Label = $ItemInfo/PanelContainer/VBoxContainer/ItemAmountLabel
@onready var item_description: RichTextLabel = $ItemInfo/PanelContainer/VBoxContainer/ItemDescription
@onready var back_button: Button = $ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/BackButton
@onready var buy_button: Button = $ItemInfo/PanelContainer/VBoxContainer/HBoxContainer/BuyButton


func open(shop_id: StringName) -> void:
	if _shop_id == shop_id:
		return
	_shop_id = shop_id
	_fetch_shop()


func _fetch_shop() -> void:
	for child in grid_container.get_children():
		child.queue_free()

	var result: Array = await Client.request_data_await(&"shop.get", {"shop_id": _shop_id})
	if result[1] != OK:
		return

	var items: Array = result[0].get("items", [])
	for entry: Dictionary in items:
		var item_id: int = entry.get("id", 0)
		var price: int = entry.get("price", 0)
		if item_id <= 0:
			continue

		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		if not item:
			continue

		var item_button: Button = Button.new()
		item_button.custom_minimum_size = Vector2(64, 64)
		item_button.icon = item.item_icon
		item_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_button.expand_icon = true
		item_button.text = "%d g" % price
		grid_container.add_child(item_button)

		var slot: ShopSlot = ShopSlot.new()
		slot.button = item_button
		slot.item_id = item_id
		slot.item = item
		slot.price = price
		item_button.pressed.connect(_on_item_slot_pressed.bind(slot))


func _on_close_button_pressed() -> void:
	hide()


func _on_item_slot_pressed(slot: ShopSlot) -> void:
	item_preview_icon.texture = slot.item.item_icon
	item_amount_label.text = "Price: %d golds" % slot.price
	item_description.text = slot.item.description
	_selected_slot = slot
	if not item_info.gui_input.is_connected(_on_item_info_gui_input):
		item_info.gui_input.connect(_on_item_info_gui_input)
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

	buy_button.disabled = false
	back_button.disabled = false

	if result[1] != OK:
		return

	var data: Dictionary = result[0]
	if not data.get("ok", false):
		item_amount_label.text = "Not enough golds! (Price: %d g)" % _selected_slot.price
		return

	_close_item_info()


class ShopSlot:
	var button: Button
	var item_id: int
	var item: Item
	var price: int
