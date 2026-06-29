extends MenuShell
## Two-panel trade window on the shared [MenuShell]. Left = YOUR offer (editable when seated),
## right = the other player's offer (read-only). Each side is a 6-slot item grid + gold + a green
## "Ready" line. Add items from a scrollable popup grid of your bag; set gold with the spinbox + Set
## (no per-tick spam). Closing keeps your seat (your offer stays on the world table — reopen to
## adjust, or Leave) so you can step out to chat. Both accept -> a 12s countdown (here AND on the
## world table) -> the server swaps atomically, then both auto-leave + the panel closes.
##
## Colours match the in-world labels + spar banner: seat 0 = gold, seat 1 = blue, so "whose item is
## whose" is the same association everywhere. Server stays authoritative on the swap.

const SLOTS: int = 6 # mirrors TradeTable.MAX_OFFER_ITEMS (distinct items per offer)
const SEAT_COLORS: Array[Color] = [Color(0.96, 0.74, 0.16), Color(0.45, 0.7, 1.0)] # gold, blue
const READY_COLOR: Color = Color(0.5, 0.9, 0.5)
const MUTED_COLOR: Color = Color(0.6, 0.62, 0.7)
const SLOT_SIZE: Vector2 = Vector2(54, 54)

var _table_id: int
var _owned: Dictionary       # item_id -> owned count (non-currency), latest inventory fetch
var _owned_gold: int
var _my_items: Dictionary    # item_id -> amount, my current offer (authoritative from broadcast)
var _my_gold: int
var _my_accepted: bool
var _seated: bool
var _picker_open: bool
var _gold_pending: bool      # true while picking gold before pressing Set (guards server re-renders)
var _countdown_tween: Tween

# --- Built once in _build_body ---
var _you_name: Label
var _you_grid: GridContainer
var _you_placeholder: Label      # shown instead of the grid when not seated
var _gold_row: HBoxContainer
var _gold_spin: SpinBox
var _add_button: Button
var _you_ready: Label
var _them_name: Label
var _them_grid: GridContainer
var _them_gold: Label
var _them_ready: Label
var _picker_overlay: Control
var _picker_grid: GridContainer
var _countdown_label: Label
var _accept_button: Button
var _leave_button: Button
var _join_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_shell("Trade")
	_build_body()
	_build_picker_overlay()
	close_requested.connect(func() -> void: ClientState.set_viewed_trade(0)) # Close keeps the seat
	hide()
	ClientState.viewed_trade_changed.connect(_on_viewed_changed)
	Client.subscribe(&"trade.table", _on_table_state)
	Client.subscribe(&"trade.result", _on_trade_result)


func _build_body() -> void:
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	content.add_child(body)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 14)
	body.add_child(columns)
	columns.add_child(_build_your_column())
	columns.add_child(VSeparator.new())
	columns.add_child(_build_their_column())

	body.add_child(HSeparator.new())
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 8)
	body.add_child(footer)
	_countdown_label = Label.new()
	_countdown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_countdown_label.add_theme_color_override(&"font_color", READY_COLOR)
	footer.add_child(_countdown_label)
	_join_button = _make_action("Join", _on_join)
	_leave_button = _make_action("Leave", _on_leave)
	_accept_button = _make_action("Accept", _on_accept)
	footer.add_child(_join_button)
	footer.add_child(_leave_button)
	footer.add_child(_accept_button)


func _build_your_column() -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	_you_name = _column_header(col, "Your offer")
	_you_grid = _make_grid()
	col.add_child(_you_grid)
	_you_placeholder = Label.new()
	_you_placeholder.text = "Join to make an offer."
	_you_placeholder.add_theme_color_override(&"font_color", MUTED_COLOR)
	_you_placeholder.visible = false
	col.add_child(_you_placeholder)

	_gold_row = HBoxContainer.new()
	_gold_row.add_theme_constant_override(&"separation", 6)
	col.add_child(_gold_row)
	var gold_label: Label = Label.new()
	gold_label.text = "Gold"
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_row.add_child(gold_label)
	_gold_spin = SpinBox.new()
	_gold_spin.min_value = 0
	_gold_spin.step = 1
	_gold_spin.value_changed.connect(_on_gold_spin_pending)
	_gold_row.add_child(_gold_spin)
	_gold_row.add_child(_make_action("Set", _on_set_gold))

	_add_button = _make_action("Add item", _toggle_picker)
	_add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_add_button)

	_you_ready = Label.new()
	col.add_child(_you_ready)
	return col


func _build_their_column() -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	_them_name = _column_header(col, "Their offer")
	_them_grid = _make_grid()
	col.add_child(_them_grid)
	_them_gold = Label.new()
	col.add_child(_them_gold)
	_them_ready = Label.new()
	col.add_child(_them_ready)
	return col


## "Add item" popup: a scrollable grid of your bag (icons), capped in height so it can't overflow
## the screen the way the old one-column list did. Click an item to drop one into your offer.
## The add-item picker is a centred popup OVER the card (inline overflowed the screen). A dim
## catches clicks-outside to close; pick icons to add — the offer behind updates live.
func _build_picker_overlay() -> void:
	_picker_overlay = Control.new()
	_picker_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker_overlay.visible = false
	add_child(_picker_overlay) # last child of the shell -> draws on top of the card

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.5)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			_toggle_picker())
	_picker_overlay.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 0)
	center.add_child(card)
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	pad.add_child(box)
	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)
	var title: Label = Label.new()
	title.text = "Add from your bag"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	header.add_child(title)
	header.add_child(_make_action("Done", _toggle_picker))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(336, 252) # fixed box -> scrolls, never grows off-screen
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_picker_grid = GridContainer.new()
	_picker_grid.columns = 5
	scroll.add_child(_picker_grid)


# --- Open / refresh ---

func _on_viewed_changed(table_id: int) -> void:
	_table_id = table_id
	if table_id > 0:
		_picker_open = false
		_gold_pending = false
		show()
		_refresh()
	else:
		hide()


func _refresh() -> void:
	if InstanceClient.current == null:
		return
	var inv: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if not is_instance_valid(self) or not visible:
		return
	if inv[1] == OK:
		_recompute_owned(inv[0])
	var state: Array = await Client.request_data_await(&"trade.state", {"table": _table_id}, InstanceClient.current.name)
	if not is_instance_valid(self) or not visible:
		return
	if state[1] == OK:
		_render(state[0])


func _recompute_owned(inventory: Dictionary) -> void:
	_owned.clear()
	_owned_gold = 0
	for slot_uid: Variant in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		var amount: int = int(data.get("a", 0))
		if item_id == Economy.gold_id():
			_owned_gold += amount
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		if item == null or item.is_currency:
			continue
		_owned[item_id] = int(_owned.get(item_id, 0)) + amount


func _on_table_state(data: Dictionary) -> void:
	if not visible or int(data.get("id", 0)) != _table_id:
		return
	_render(data)


# --- Render ---

func _render(data: Dictionary) -> void:
	var seats: Array = data.get("seats", [])
	var my_index: int = -1
	for i: int in seats.size():
		if int(seats[i].get("id", 0)) == ClientState.player_id:
			my_index = i
	_seated = my_index >= 0

	var mine: Dictionary = seats[my_index] if my_index >= 0 else {}
	var other_index: int = -1
	for i: int in seats.size():
		if i != my_index and not str(seats[i].get("name", "")).is_empty():
			other_index = i
			break
	var other: Dictionary = seats[other_index] if other_index >= 0 else {}
	var free_seat: bool = seats.any(func(s: Dictionary) -> bool: return str(s.get("name", "")).is_empty())

	_render_you(mine, my_index if my_index >= 0 else 0)
	_render_them(other, other_index if other_index >= 0 else 1)
	_render_footer(data, free_seat)


func _render_you(mine: Dictionary, seat_index: int) -> void:
	_you_name.add_theme_color_override(&"font_color", SEAT_COLORS[seat_index % SEAT_COLORS.size()])
	_you_name.text = "Your offer" if _seated else "Open seat"
	_you_grid.visible = _seated
	_you_placeholder.visible = not _seated
	_gold_row.visible = _seated
	_add_button.visible = _seated
	_you_ready.visible = _seated
	if not _seated:
		_picker_overlay.visible = false
		_picker_open = false
		return

	_my_items = {}
	for item: Dictionary in mine.get("items", []):
		_my_items[int(item.get("id", 0))] = int(item.get("amount", 0))
	_my_gold = int(mine.get("gold", 0))
	_my_accepted = bool(mine.get("accepted", false))

	_fill_grid(_you_grid, _my_items, true)
	_gold_spin.max_value = maxf(1, _owned_gold)
	if not _gold_pending: # don't clobber an amount you're mid-picking
		_gold_spin.set_value_no_signal(_my_gold)
	_add_button.disabled = _my_items.size() >= SLOTS
	_set_ready_line(_you_ready, _my_accepted)
	if _picker_open:
		_rebuild_picker()


func _render_them(other: Dictionary, seat_index: int) -> void:
	_them_name.add_theme_color_override(&"font_color", SEAT_COLORS[seat_index % SEAT_COLORS.size()])
	var their_name: String = str(other.get("name", ""))
	if their_name.is_empty():
		_them_name.text = "Waiting for a player"
		_fill_grid(_them_grid, {}, false)
		_them_gold.text = ""
		_them_ready.text = ""
		return
	_them_name.text = "%s's offer" % their_name
	var their_items: Dictionary = {}
	for item: Dictionary in other.get("items", []):
		their_items[int(item.get("id", 0))] = int(item.get("amount", 0))
	_fill_grid(_them_grid, their_items, false)
	var their_gold: int = int(other.get("gold", 0))
	_them_gold.text = "Gold: %d" % their_gold if their_gold > 0 else "Gold: 0"
	_set_ready_line(_them_ready, bool(other.get("accepted", false)))


func _render_footer(data: Dictionary, free_seat: bool) -> void:
	_join_button.visible = not _seated and free_seat
	_join_button.text = "Join  (%dg)" % int(data.get("join_cost", 0))
	_leave_button.visible = _seated
	_accept_button.visible = _seated
	_accept_button.text = "Unaccept" if _my_accepted else "Accept"
	var countdown: int = int(data.get("countdown", 0))
	if countdown > 0:
		_run_countdown(countdown)
	else:
		_stop_countdown()


## Rebuild a side's grid: filled item slots first, then empty placeholders up to SLOTS.
func _fill_grid(grid: GridContainer, items: Dictionary, mine: bool) -> void:
	for child: Node in grid.get_children():
		child.queue_free()
	var count: int = 0
	for item_id: int in items:
		grid.add_child(_make_slot(item_id, int(items[item_id]), mine))
		count += 1
	for _i: int in maxi(0, SLOTS - count):
		grid.add_child(_make_empty_slot(mine))


func _make_slot(item_id: int, amount: int, mine: bool) -> Button:
	var slot: Button = Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.clip_contents = true
	slot.focus_mode = Control.FOCUS_NONE
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if item != null:
		PixelIcon.mount(slot, item.item_icon)
		slot.tooltip_text = str(item.item_name)
	slot.add_child(_count_badge(amount))
	if mine:
		slot.pressed.connect(_remove_from_offer.bind(item_id)) # click to take one back
	else:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE # read-only — NOT disabled, so the icon stays bright
	return slot


func _make_empty_slot(mine: bool) -> Button:
	var slot: Button = Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.focus_mode = Control.FOCUS_NONE
	slot.modulate = Color(1, 1, 1, 0.4)
	if mine:
		slot.pressed.connect(_open_picker) # an empty slot is a shortcut to the add-item grid
	else:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


## A small "xN" count pinned to a slot's bottom-right. Auto-sizes (PRESET, no fixed offsets) so it
## never clips, with an outline so it reads over a bright icon. Used by offer slots + the picker.
func _count_badge(amount: int) -> Label:
	var badge: Label = Label.new()
	badge.text = "x%d" % amount
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	badge.add_theme_constant_override(&"outline_size", 4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


# --- Offer edits ---

func _add_to_offer(item_id: int) -> void:
	var owned: int = int(_owned.get(item_id, 0))
	if owned <= 0:
		return
	if _my_items.has(item_id):
		_my_items[item_id] = mini(int(_my_items[item_id]) + 1, owned)
	elif _my_items.size() < SLOTS:
		_my_items[item_id] = 1
	else:
		Toaster.toast("Your offer is full (%d items max)." % SLOTS)
		return
	_send_offer()


func _remove_from_offer(item_id: int) -> void:
	var amount: int = int(_my_items.get(item_id, 0)) - 1
	if amount > 0:
		_my_items[item_id] = amount
	else:
		_my_items.erase(item_id)
	_send_offer()


func _send_offer() -> void:
	Client.request_data(&"trade.offer", Callable(), {"table": _table_id, "items": _my_items, "gold": _my_gold}, InstanceClient.current.name)


func _on_set_gold() -> void:
	_my_gold = int(_gold_spin.value)
	_gold_pending = false
	_send_offer()


func _on_gold_spin_pending(_value: float) -> void:
	_gold_pending = true # mark dirty; commit only on Set (no per-tick network spam)


# --- Add-item picker ---

func _open_picker() -> void:
	_picker_open = true
	_picker_overlay.visible = true
	_rebuild_picker()


func _toggle_picker() -> void:
	_picker_open = not _picker_open
	_picker_overlay.visible = _picker_open
	if _picker_open:
		_rebuild_picker()


func _rebuild_picker() -> void:
	for child: Node in _picker_grid.get_children():
		child.queue_free()
	var any: bool = false
	for item_id: int in _owned:
		if int(_owned[item_id]) <= 0:
			continue
		any = true
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
		var button: Button = Button.new()
		button.custom_minimum_size = SLOT_SIZE
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		if item != null:
			PixelIcon.mount(button, item.item_icon)
			button.tooltip_text = "%s  (have %d)" % [str(item.item_name), int(_owned[item_id])]
		button.add_child(_count_badge(int(_owned[item_id]))) # how many you HAVE in your bag
		button.pressed.connect(_add_to_offer.bind(item_id))
		_picker_grid.add_child(button)
	if not any:
		var empty: Label = Label.new()
		empty.text = "Your bag is empty."
		empty.add_theme_color_override(&"font_color", MUTED_COLOR)
		_picker_grid.add_child(empty)


# --- Actions ---

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
			Toaster.toast("Too far from the trade table.")


func _on_accept() -> void:
	Client.request_data(&"trade.accept", Callable(), {"table": _table_id, "accepted": not _my_accepted}, InstanceClient.current.name)


func _on_leave() -> void:
	Client.request_data(&"trade.leave", Callable(), {"table": _table_id}, InstanceClient.current.name)


func _on_trade_result(data: Dictionary) -> void:
	Toaster.toast(_received_summary(data.get("received", {})) if data.get("ok", false) else "Trade failed.")
	# Auto-leave + close so the table frees up for the next pair (only the two traders get this push).
	if _table_id > 0:
		Client.request_data(&"trade.leave", Callable(), {"table": _table_id}, InstanceClient.current.name)
	ClientState.set_viewed_trade(0)


## "Received 2x Iron Sword, 50 gold." from the server's offer summary (falls back if you got nothing).
func _received_summary(received: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: Dictionary in received.get("items", []):
		parts.append("%dx %s" % [int(item.get("amount", 1)), str(item.get("name", "?"))])
	var gold: int = int(received.get("gold", 0))
	if gold > 0:
		parts.append("%d gold" % gold)
	if parts.is_empty():
		return "Trade complete!"
	return "Received " + ", ".join(parts) + "."


# --- Countdown (tweened; cancelled by a countdown == 0 push) ---

func _run_countdown(seconds: int) -> void:
	_stop_countdown()
	_countdown_tween = create_tween()
	_countdown_tween.tween_method(_set_countdown_text, float(seconds), 0.0, float(seconds))


func _set_countdown_text(value: float) -> void:
	_countdown_label.text = "Trade completes in %d…" % maxi(1, ceili(value))


func _stop_countdown() -> void:
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = null
	_countdown_label.text = ""


# --- Helpers ---

func _column_header(col: VBoxContainer, caption: String) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	col.add_child(row)
	var cap: Label = Label.new()
	cap.text = caption
	cap.add_theme_color_override(&"font_color", MUTED_COLOR)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	var name_label: Label = Label.new()
	name_label.add_theme_font_size_override(&"font_size", 14)
	row.add_child(name_label)
	return name_label


func _make_grid() -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	return grid


func _make_action(text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button


## Green "Ready" when accepted, muted "Choosing…" otherwise — replaces the old "✓" glyph + em-dash.
func _set_ready_line(label: Label, accepted: bool) -> void:
	label.text = "Ready" if accepted else "Choosing…"
	label.add_theme_color_override(&"font_color", READY_COLOR if accepted else MUTED_COLOR)
