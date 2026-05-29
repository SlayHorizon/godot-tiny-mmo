extends Control
## Centered, non-blocking trade panel. Opening (clicking a table) just views it; you
## explicitly Join a seat (costs gold). Closing the panel does NOT leave your seat —
## your offer stays on the world table; reopen to adjust or Leave (or walk away). Only
## the card itself blocks input, so you can still move/chat while it's open.

var _table_id: int
## item_id -> owned count (non-currency), from the latest inventory fetch.
var _owned: Dictionary
var _owned_gold: int
## MY offer (authoritative from broadcast): item_id -> amount, and gold.
var _my_items: Dictionary
var _my_gold: int
var _my_accepted: bool
var _seated: bool
var _picker_open: bool

var _countdown_label: Label
var _table_label: Label
var _join_button: Button
var _seated_box: VBoxContainer
var _gold_spin: SpinBox
var _offer_box: VBoxContainer
var _add_button: Button
var _picker_box: VBoxContainer
var _accept_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # only the card blocks input
	_build()
	hide()
	ClientState.viewed_trade_changed.connect(_on_viewed_changed)
	Client.subscribe(&"trade.table", _on_table_state)
	Client.subscribe(&"trade.result", _on_trade_result)


func _build() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(340, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 6)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)
	var title: Label = Label.new()
	title.text = "Trade"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): ClientState.set_viewed_trade(0))
	header.add_child(close_button)

	_countdown_label = Label.new()
	_countdown_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
	root.add_child(_countdown_label)

	_table_label = Label.new()
	_table_label.add_theme_color_override(&"font_color", Color(0.8, 0.8, 0.85))
	root.add_child(_table_label)

	_join_button = Button.new()
	_join_button.custom_minimum_size = Vector2(0, 40)
	_join_button.pressed.connect(_on_join)
	root.add_child(_join_button)

	_seated_box = VBoxContainer.new()
	_seated_box.add_theme_constant_override(&"separation", 4)
	root.add_child(_seated_box)

	var your_label: Label = Label.new()
	your_label.text = "Your offer:"
	_seated_box.add_child(your_label)

	var gold_row: HBoxContainer = HBoxContainer.new()
	_seated_box.add_child(gold_row)
	var gold_label: Label = Label.new()
	gold_label.text = "Gold"
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(gold_label)
	_gold_spin = SpinBox.new()
	_gold_spin.min_value = 0
	_gold_spin.step = 1
	_gold_spin.value_changed.connect(_on_gold_changed)
	gold_row.add_child(_gold_spin)

	_offer_box = VBoxContainer.new()
	_seated_box.add_child(_offer_box)

	_add_button = Button.new()
	_add_button.text = "Add item"
	_add_button.pressed.connect(_toggle_picker)
	_seated_box.add_child(_add_button)

	_picker_box = VBoxContainer.new()
	_picker_box.visible = false
	_seated_box.add_child(_picker_box)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	_seated_box.add_child(actions)
	_accept_button = Button.new()
	_accept_button.custom_minimum_size = Vector2(0, 40)
	_accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accept_button.pressed.connect(_on_accept)
	actions.add_child(_accept_button)
	var leave_button: Button = Button.new()
	leave_button.text = "Leave"
	leave_button.custom_minimum_size = Vector2(0, 40)
	leave_button.pressed.connect(_on_leave)
	actions.add_child(leave_button)


func _on_viewed_changed(table_id: int) -> void:
	_table_id = table_id
	if table_id > 0:
		_picker_open = false
		show()
		_refresh()
	else:
		hide()


func _refresh() -> void:
	var inv_result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if inv_result[1] == OK:
		_recompute_owned(inv_result[0])
	var state_result: Array = await Client.request_data_await(&"trade.state", {"table": _table_id}, InstanceClient.current.name)
	if state_result[1] == OK:
		_render(state_result[0])


func _recompute_owned(inventory: Dictionary) -> void:
	_owned.clear()
	_owned_gold = 0
	for slot_uid in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		var amount: int = int(data.get("a", 0))
		if item_id == Economy.gold_id():
			_owned_gold += amount
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		if item == null or item.is_currency:
			continue
		_owned[item_id] = _owned.get(item_id, 0) + amount


func _on_table_state(data: Dictionary) -> void:
	if not visible or int(data.get("id", 0)) != _table_id:
		return
	_render(data)


func _render(data: Dictionary) -> void:
	var seats: Array = data.get("seats", [])
	var mine: Dictionary = {}
	var other: Dictionary = {}
	var has_free_seat: bool = false
	for i: int in seats.size():
		if int(seats[i].get("id", 0)) == ClientState.player_id:
			mine = seats[i]
			other = seats[1 - i] if seats.size() > 1 else {}
		elif int(seats[i].get("id", 0)) == 0:
			has_free_seat = true

	_seated = not mine.is_empty()

	var countdown: int = int(data.get("countdown", 0))
	_countdown_label.text = "Trade completes in %d…" % countdown if countdown > 0 else ""

	if _seated:
		_table_label.text = _format_offer(other, "They offer")
		_seated_box.visible = true
		_join_button.visible = false
		_render_seated(mine)
	else:
		_table_label.text = _format_table(seats)
		_seated_box.visible = false
		_join_button.visible = has_free_seat
		_join_button.text = "Join  (%dg)" % int(data.get("join_cost", 0))


func _render_seated(mine: Dictionary) -> void:
	_my_gold = int(mine.get("gold", 0))
	_my_accepted = bool(mine.get("accepted", false))
	_my_items = {}
	for item: Dictionary in mine.get("items", []):
		_my_items[int(item.get("id", 0))] = int(item.get("amount", 0))

	_gold_spin.max_value = _owned_gold
	_gold_spin.set_value_no_signal(_my_gold)
	_accept_button.text = "Unaccept" if _my_accepted else "Accept"
	_add_button.disabled = _my_items.size() >= TradeTable.MAX_OFFER_ITEMS

	for child in _offer_box.get_children():
		child.queue_free()
	for item_id in _my_items:
		_offer_box.add_child(_make_offer_row(int(item_id)))

	_picker_box.visible = _picker_open
	if _picker_open:
		_rebuild_picker()


func _make_offer_row(item_id: int) -> HBoxContainer:
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	var in_offer: int = int(_my_items.get(item_id, 0))
	var owned: int = int(_owned.get(item_id, 0))

	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s  %d/%d" % [str(item.item_name) if item else "?", in_offer, owned]
	row.add_child(label)

	var minus: Button = Button.new()
	minus.text = "-"
	minus.pressed.connect(_change_item.bind(item_id, -1))
	row.add_child(minus)

	var plus: Button = Button.new()
	plus.text = "+"
	plus.disabled = in_offer >= owned
	plus.pressed.connect(_change_item.bind(item_id, 1))
	row.add_child(plus)
	return row


func _toggle_picker() -> void:
	_picker_open = not _picker_open
	_picker_box.visible = _picker_open
	if _picker_open:
		_rebuild_picker()


## Lists owned items not yet in the offer (to add a new item type).
func _rebuild_picker() -> void:
	for child in _picker_box.get_children():
		child.queue_free()
	var added_any: bool = false
	for item_id in _owned:
		if _my_items.has(item_id) or int(_owned[item_id]) <= 0:
			continue
		added_any = true
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(item_id))
		var button: Button = Button.new()
		button.text = "+ %s (%d)" % [str(item.item_name) if item else "?", int(_owned[item_id])]
		button.pressed.connect(_add_new_item.bind(int(item_id)))
		_picker_box.add_child(button)
	if not added_any:
		var empty: Label = Label.new()
		empty.text = "Nothing else to add."
		_picker_box.add_child(empty)


func _add_new_item(item_id: int) -> void:
	if _my_items.size() >= TradeTable.MAX_OFFER_ITEMS:
		return
	_my_items[item_id] = 1
	_picker_open = false
	_send_offer()


func _change_item(item_id: int, delta: int) -> void:
	var amount: int = clampi(int(_my_items.get(item_id, 0)) + delta, 0, int(_owned.get(item_id, 0)))
	if amount > 0:
		_my_items[item_id] = amount
	else:
		_my_items.erase(item_id)
	_send_offer()


func _on_gold_changed(value: float) -> void:
	_my_gold = int(value)
	_send_offer()


func _send_offer() -> void:
	Client.request_data(&"trade.offer", Callable(), {"table": _table_id, "items": _my_items, "gold": _my_gold}, InstanceClient.current.name)


func _on_join() -> void:
	Client.request_data(&"trade.join", _on_join_result, {"table": _table_id}, InstanceClient.current.name)


func _on_join_result(data: Dictionary) -> void:
	if data.get("ok", false):
		return
	match String(data.get("reason", "")):
		"gold":
			Toaster.toast("Not enough gold to join.")
		"full":
			Toaster.toast("This table is full.")
		"too_far":
			Toaster.toast("Step up to the table to join.")


func _on_accept() -> void:
	Client.request_data(&"trade.accept", Callable(), {"table": _table_id, "accepted": not _my_accepted}, InstanceClient.current.name)


## Leaves the seat but keeps the panel open (so you can re-join or just watch).
func _on_leave() -> void:
	Client.request_data(&"trade.leave", Callable(), {"table": _table_id}, InstanceClient.current.name)


func _on_trade_result(data: Dictionary) -> void:
	Toaster.toast("Trade complete!" if data.get("ok", false) else "Trade failed.")
	if visible:
		_refresh()


# --- Formatting ---

func _format_offer(seat: Dictionary, prefix: String) -> String:
	# Local was named `name` which shadowed Node.name — renamed so future
	# refactors can't accidentally reach for `self.name` and get the wrong thing.
	var seat_name: String = str(seat.get("name", ""))
	if seat_name.is_empty():
		return "Waiting for another player…"
	var text: String = "%s — %s%s:" % [seat_name, prefix, " ✓" if seat.get("accepted", false) else ""]
	for item: Dictionary in seat.get("items", []):
		text += "\n  %dx %s" % [int(item.get("amount", 1)), str(item.get("name", ""))]
	var gold: int = int(seat.get("gold", 0))
	if gold > 0:
		text += "\n  %dg" % gold
	return text


func _format_table(seats: Array) -> String:
	var lines: PackedStringArray = []
	for seat: Dictionary in seats:
		if not str(seat.get("name", "")).is_empty():
			lines.append(_format_offer(seat, "offers"))
	if lines.is_empty():
		return "This table is free."
	return "\n".join(lines)
