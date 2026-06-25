extends MenuShell


enum Mode { BUY, SELL }

const STOCK_INFINITE_TEXT: String = "∞"

var _shop: ShopResource
var _shop_id: int
var _mode: Mode
var _golds: int
## Registry id of the gold currency item (the player's balance is its inventory count).
var _gold_id: int
## The currency this shop trades in (gold by default; e.g. event tokens for a
## fair stall). Drives the header balance chip + affordability.
var _currency_id: int
var _slots: Array[ShopSlot]
var _selected_slot: ShopSlot
## Raw inventory (slot_uid -> {"id", "a"}), fetched on open and after each transaction.
var _inventory: Dictionary
## item_id -> total owned, derived from _inventory (for the Buy-mode owned count).
var _owned: Dictionary[int, int]
## item_ids the local player currently has equipped (can't be sold). Refreshed per list build.
var _equipped_ids: Array

## Header widgets, created in the shell header at runtime.
var mode_tabs: HBoxContainer
var buy_tab: Button
var sell_tab: Button
var golds_icon: TextureRect
var golds_label: Label
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
	_gold_id = Economy.gold_id()
	_currency_id = _gold_id
	# Wrap the authored Body in the shared menu shell (banner header + card).
	build_shell("Shop", $Body, true)
	_build_header()

	buy_tab.pressed.connect(_set_mode.bind(Mode.BUY))
	sell_tab.pressed.connect(_set_mode.bind(Mode.SELL))
	quantity_spinbox.value_changed.connect(_on_quantity_changed)
	max_button.pressed.connect(func(): quantity_spinbox.value = quantity_spinbox.max_value)


## Builds the header content: Buy/Sell mode tabs (centre, like the character
## menu) and a currency icon + balance (top-right, next to Close). Using an
## icon instead of the word "Golds" keeps it ready for alt-currency shops.
func _build_header() -> void:
	mode_tabs = HBoxContainer.new()
	mode_tabs.add_theme_constant_override(&"separation", 6)
	header_center.add_child(mode_tabs)
	buy_tab = _make_mode_tab("Buy")
	sell_tab = _make_mode_tab("Sell")
	mode_tabs.add_child(buy_tab)
	mode_tabs.add_child(sell_tab)

	golds_icon = TextureRect.new()
	golds_icon.custom_minimum_size = Vector2(20, 20)
	golds_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	golds_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var gold: Item = ContentRegistryHub.load_by_id(&"items", _gold_id)
	if gold:
		golds_icon.texture = gold.item_icon
	golds_label = Label.new()
	golds_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	golds_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Insert before the Close button (added by build_shell at index 0).
	header_right.add_child(golds_icon)
	header_right.add_child(golds_label)
	header_right.move_child(golds_icon, 0)
	header_right.move_child(golds_label, 1)


func _make_mode_tab(text: String) -> Button:
	var tab: Button = Button.new()
	tab.text = text
	tab.theme_type_variation = &"HeaderTab"
	tab.toggle_mode = true
	tab.custom_minimum_size = Vector2(104, 0)
	return tab


func open(shop_id: int) -> void:
	_shop_id = shop_id
	# Shop contents are static client-side data — render from the local ShopResource.
	_shop = ShopResource.load_shop(shop_id)
	if not _shop:
		return
	if not _shop.shop_name.is_empty():
		set_title(_shop.shop_name)
	# Resolve the shop's currency and point the header chip at its icon.
	_currency_id = _shop.display_currency_id()
	var currency: Item = ContentRegistryHub.load_by_id(&"items", _currency_id)
	if currency and golds_icon:
		golds_icon.texture = currency.item_icon
	# Tab bar shown if the shop offers both flavors of interaction. Specialty trades
	# live inside the Sell tab and force it open even when generic sells are off.
	var has_sell_side: bool = _shop.allows_selling() or _shop.has_trades()
	mode_tabs.visible = _shop.allows_buying() and has_sell_side
	# Hide the unused tab so the available one is obviously the active one.
	sell_tab.visible = has_sell_side
	buy_tab.visible = _shop.allows_buying()
	_set_mode(Mode.SELL if not _shop.allows_buying() else Mode.BUY)
	# Dynamic/authoritative bits from the server.
	_request_open()
	_request_inventory()


func _set_mode(mode: Mode) -> void:
	_mode = mode
	buy_tab.button_pressed = mode == Mode.BUY
	sell_tab.button_pressed = mode == Mode.SELL
	_build_list()
	_clear_detail()


## Build the row list synchronously (no await -> double-emit can't duplicate rows).
func _build_list() -> void:
	# Guard against an in-flight inventory request firing back after a second
	# open() has cleared _shop (e.g. when the player clicks a shop whose id
	# doesn't resolve in the registry — open() bails, but the async fetch from
	# the previous shop can still try to rebuild).
	if _shop == null:
		return
	for child in item_list.get_children():
		child.queue_free()
	_slots.clear()

	if _mode == Mode.BUY:
		_build_buy_rows()
	else:
		_equipped_ids = _get_equipped_ids()
		_build_trade_rows()
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
	# Specialty vendors (those with declared trades) refuse generic junk —
	# the only sell-side affordance is the trade rows.
	if not _shop.allows_selling() or _shop.has_trades():
		return
	for slot_uid in _inventory:
		var data: Dictionary = _inventory[slot_uid]
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(data.get("id", 0)))
		if item == null or item.is_currency or item.vendor_value <= 0:
			continue # not sellable to vendors
		var slot: ShopSlot = ShopSlot.new()
		slot.item = item
		slot.item_id = int(data.get("id", 0))
		slot.price = item.vendor_value
		slot.slot_uid = int(slot_uid)
		slot.quantity = int(data.get("a", 0))
		_add_row(slot, str(slot.quantity))


## Specialty vendor trades — fixed item/amount/payout bundles, listed before
## generic sell rows so the player sees them first.
func _build_trade_rows() -> void:
	if _shop.accepted_trades.is_empty():
		return
	for i in _shop.accepted_trades.size():
		var trade: ShopTrade = _shop.accepted_trades[i]
		if trade == null or trade.item == null or trade.amount <= 0:
			continue
		var item_id: int = int(trade.item.get_meta(&"id", 0))
		var owned: int = _owned.get(item_id, 0)
		@warning_ignore("integer_division")
		var bundles_available: int = owned / trade.amount
		var slot: ShopSlot = ShopSlot.new()
		slot.item = trade.item
		slot.item_id = item_id
		slot.price = trade.payout
		slot.quantity = owned
		slot.is_trade = true
		slot.trade_index = i
		slot.trade_amount = trade.amount
		slot.trade_payout = trade.payout
		slot.trade_bundles_available = bundles_available
		var middle: String = "x%d → %d g" % [trade.amount, trade.payout]
		_add_row(slot, middle)


func _add_row(slot: ShopSlot, middle_text: String) -> void:
	slot.button = _make_row(slot.item, middle_text, slot.price)
	slot.button.pressed.connect(_on_row_pressed.bind(slot))
	item_list.add_child(slot.button)
	_slots.append(slot)


func _make_row(item: Item, middle_text: String, price: int) -> Button:
	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, 64)
	row.focus_mode = Control.FOCUS_ALL
	# PASS (not the Button default STOP) lets a touch/mouse drag fall through to the
	# ScrollContainer so the list drag-scrolls, while a tap still presses the row; the
	# container's scroll_deadzone is what tells a tap from a drag.
	row.mouse_filter = Control.MOUSE_FILTER_PASS

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
	# Currency-neutral: the header chip shows which currency these prices are in.
	hbox.add_child(_column(str(price), 88, HORIZONTAL_ALIGNMENT_CENTER))

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
		# The expanding name column clips with an ellipsis so a long item name
		# can't widen the row and push the menu out (rows stay uniform).
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _on_row_pressed(slot: ShopSlot) -> void:
	_selected_slot = slot
	detail_icon.texture = slot.item.item_icon
	detail_name_label.text = str(slot.item.item_name)
	detail_description.bbcode_enabled = true
	detail_description.text = ItemTooltip.body(slot.item)
	quantity_row.visible = true
	quantity_spinbox.set_value_no_signal(1)
	_update_quantity_bounds()
	_update_price_label()
	_update_owned_label()
	if _mode == Mode.SELL:
		if slot.is_trade:
			action_button.text = "Trade"
			action_button.disabled = slot.trade_bundles_available <= 0
		elif slot.item_id in _equipped_ids:
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


## Cap the quantity spinbox at what's affordable (buy) / owned (sell) /
## bundles available (trade).
func _update_quantity_bounds() -> void:
	if _selected_slot == null:
		return
	var max_qty: int
	if _mode == Mode.SELL:
		if _selected_slot.is_trade:
			max_qty = maxi(1, _selected_slot.trade_bundles_available)
		else:
			max_qty = maxi(1, _selected_slot.quantity)
	else:
		max_qty = maxi(1, _affordable_count(_selected_slot.price))
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
	var bundles: int = int(quantity_spinbox.value)
	if _mode == Mode.SELL and _selected_slot.is_trade:
		detail_price_label.text = "Trade: %d %s → %d golds" % [
			_selected_slot.trade_amount * bundles,
			_selected_slot.item.item_name,
			_selected_slot.trade_payout * bundles,
		]
		return
	var total: int = _selected_slot.price * bundles
	# Value first, caption last, right-aligned — keeps the caption pinned to the
	# right edge so it doesn't jitter when the number's width changes between
	# items (the Zelda "30  Price" layout).
	detail_price_label.text = (
		"%d   Value" % total if _mode == Mode.SELL
		else "%d   Price" % total
	)


func _update_owned_label() -> void:
	if _selected_slot == null:
		detail_owned_label.text = ""
		return
	var owned: int = _selected_slot.quantity if _mode == Mode.SELL else _owned.get(_selected_slot.item_id, 0)
	detail_owned_label.text = "%d   In inventory" % owned


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
			# Trade rows dim when the player can't complete even one bundle.
			# Generic-sell rows dim when the item is currently equipped (can't sell).
			var dim: bool = (
				slot.trade_bundles_available <= 0 if slot.is_trade
				else slot.item_id in _equipped_ids
			)
			slot.button.modulate = Color(1.0, 1.0, 1.0, 0.45) if dim else Color.WHITE


func _set_golds(value: int) -> void:
	_golds = value
	golds_label.text = "%d" % _golds


## Authorize opening the shop (gold + contents come from elsewhere).
func _request_open() -> void:
	# Target the player's CURRENT instance — without it the server falls back to the
	# default (overworld) instance, where a non-overworld shop isn't registered, so
	# the auth fails and the menu closes (the "opens for a second then vanishes" bug).
	var result: Array = await Client.request_data_await(&"shop.open", {"shop_id": _shop_id}, InstanceClient.current.name)
	if result[1] != OK:
		return
	if not result[0].get("ok", false):
		hide()


## Refresh the player's inventory (gold balance, owned counts, the Sell list).
func _request_inventory() -> void:
	var result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if result[1] != OK:
		return
	_inventory = result[0]
	_recompute_owned()
	# The shop's currency is an item; the balance is its amount in inventory.
	_set_golds(_owned.get(_currency_id, 0))
	if _mode == Mode.SELL:
		_build_list()
	_refresh_affordability()
	_update_owned_label()
	if _selected_slot and _mode == Mode.BUY:
		_update_quantity_bounds()
		_refresh_buy_action()


func _recompute_owned() -> void:
	_owned.clear()
	for slot_uid in _inventory:
		var data: Dictionary = _inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		if item_id > 0:
			_owned[item_id] = _owned.get(item_id, 0) + int(data.get("a", 0))


func _on_action_button_pressed() -> void:
	if _selected_slot == null:
		return
	if _mode == Mode.BUY:
		_buy()
	elif _selected_slot.is_trade:
		_trade()
	else:
		_sell()


func _buy() -> void:
	var amount: int = int(quantity_spinbox.value)
	action_button.disabled = true
	var result: Array = await Client.request_data_await(
		&"shop.buy.item",
		{"shop_id": _shop_id, "id": _selected_slot.item_id, "amount": amount},
		InstanceClient.current.name
	)
	if result[1] != OK or not result[0].get("ok", false):
		_refresh_buy_action()
		return
	# Gold + counts refresh from the inventory fetch.
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
		{"shop_id": _shop_id, "slot_uid": slot_uid, "amount": amount},
		InstanceClient.current.name
	)
	if result[1] != OK or not result[0].get("ok", false):
		action_button.disabled = false
		return
	# Gold + counts refresh from the inventory fetch.
	await _request_inventory() # rebuilds the Sell list with updated quantities
	# Keep the same item selected if its stack still exists.
	for slot in _slots:
		if slot.slot_uid == slot_uid:
			_on_row_pressed(slot)
			return
	_clear_detail()


## Specialty vendor trade: hand over N bundles of trade.item for trade.payout * N gold.
func _trade() -> void:
	var trade_index: int = _selected_slot.trade_index
	var bundles: int = int(quantity_spinbox.value)
	action_button.disabled = true
	var result: Array = await Client.request_data_await(
		&"shop.trade.item",
		{"shop_id": _shop_id, "trade_index": trade_index, "bundles": bundles},
		InstanceClient.current.name
	)
	if result[1] != OK or not result[0].get("ok", false):
		action_button.disabled = false
		return
	# Gold + counts refresh, then keep the same trade selected so the player can repeat.
	await _request_inventory()
	for slot in _slots:
		if slot.is_trade and slot.trade_index == trade_index:
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
	## Specialty trade mode (a row that exchanges N items for M gold):
	var is_trade: bool = false
	var trade_index: int = -1
	var trade_amount: int = 0
	var trade_payout: int = 0
	var trade_bundles_available: int = 0
