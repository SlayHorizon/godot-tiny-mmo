extends MenuShell
## Inventory menu, BotW-style: top category rail (LB/RB cycle on pad), a
## sorted + grouped bag grid with equipped gear rendered as badged tiles at
## the head of their section (the Gear tab IS the paperdoll), a full-height
## detail column with stat compare, and a bottom input-hint bar. See
## docs/inventory.md.

## Rail-only pseudo filter: every favorited ("p"-flagged) bag item, any
## category, grouped by its normal sections.
const TAB_FAVORITES: int = -2
## Rail tabs in order: [label, filter]. Text-first — icons can slot in with an
## owner art pass later. No "All": weapons/armor are deliberately separate
## (equip-and-act vs silent stat buffers); Favorites / Others / Quest only
## appear while matching items are held.
const RAIL_TABS: Array[Array] = [
	["Favorites", TAB_FAVORITES],
	["Weapons", Item.InventoryTab.WEAPON],
	["Armor", Item.InventoryTab.ARMOR],
	["Consumables", Item.InventoryTab.CONSUMABLE],
	["Materials", Item.InventoryTab.MATERIAL],
	["Others", Item.InventoryTab.OTHER],
	["Quest", Item.InventoryTab.QUEST],
]
## Tabs hidden while no matching item is held.
const DYNAMIC_TABS: Array[int] = [TAB_FAVORITES, Item.InventoryTab.OTHER, Item.InventoryTab.QUEST]
## Bag sections in render order: [group key (Item.group_key()), label].
## Weapon mastery categories get their own sections, armor groups by SET —
## a group key NOT listed here still renders (appended alphabetically,
## capitalized label), so new categories / armor sets never vanish.
const GROUPS: Array[Array] = [
	[&"sword", "Swords"],
	[&"hammer", "Hammers"],
	[&"bow", "Bows"],
	[&"wand", "Wands"],
	[&"book", "Books"],
	[&"weapons", "Weapons"],
	[&"tools", "Tools"],
	[&"rings", "Rings"],
	[&"relics", "Relics"],
	[&"armor", "Armor"],
	[&"consumables", "Consumables"],
	[&"materials", "Materials"],
	[&"quest", "Quest"],
	[&"items", "Items"],
]
const GRID_COLUMNS: int = 6
const SECTION_HEADER_COLOR: Color = Color(0.56, 0.72, 0.85)
const EQUIPPED_BADGE_COLOR: Color = Color(1.0, 0.9, 0.55)
## Gear slot keys that hold REAL equipment (moved out of the bag on equip).
## The weapon slot can also hold a bag item (a potion in hand) — synthetic
## equipped tiles therefore only render for GearItems.
const EQUIP_SLOT_KEYS: Array[StringName] = [&"weapon", &"helmet", &"torso", &"boot", &"ring", &"relic"]

## Last active tab, remembered across menu opens for the whole session.
static var _session_tab: int = Item.InventoryTab.WEAPON

var _inventory: Dictionary
var _gold_id: int
var _tab_filter: int = Item.InventoryTab.WEAPON
var _filling: bool
## A refresh that arrived while one was in flight — run it after (an
## equipment_changed can land mid-fill when a weapon draw completes).
var _refill_queued: bool

## Current selection driving the detail column.
var _selected_item: Item
var _selected_item_id: int
var _selected_slot_uid: int = -1
## Set when an equipped tile is selected (Unequip mode); empty for a bag item.
var _selected_gear_slot: StringName
var _selected_pinned: bool

## Wallet widgets, created in the shell header at runtime.
var wallet_icon: TextureRect
var wallet_amount: Label
var hint_bar: InputHintBar
var _tab_buttons: Array[Button]
## One selection across every section grid — the pressed tile shows the
## theme's accent style, marking what the detail column describes.
var _tile_group: ButtonGroup = ButtonGroup.new()
## [button, entry] pairs of the current grid build, for selection restore.
var _tiles: Array
## Captured before build_shell reparents it — $MainBody stops resolving after.
var _main_body: HBoxContainer
## The Equipment view (paperdoll + gear totals), swapped with the bag via the
## shell-header Bag | Equipment tabs.
var _equipment_body: HBoxContainer
var _view_tabs: Dictionary[StringName, Button] = {}
## Crisp pixel preview mounted onto %DetailIcon (a sizing host; its own texture stays null).
var _detail_pixel: TextureRect

@onready var left_col: VBoxContainer = %LeftCol
@onready var rail_tabs: HBoxContainer = %RailTabs
@onready var lb_chip: Label = %LBChip
@onready var rb_chip: Label = %RBChip
@onready var bag_scroll: ScrollContainer = %BagScroll
@onready var section_list: VBoxContainer = %SectionList
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name: Label = %DetailName
@onready var detail_description: RichTextLabel = %DetailDescription
@onready var action_button: Button = %ActionButton
@onready var hotkey_button: Button = %HotkeyButton
@onready var pin_button: Button = %PinButton


func _ready() -> void:
	_gold_id = Economy.gold_id()
	# Wrap the authored body in the shared menu shell (banner header + card).
	_main_body = $MainBody
	_equipment_body = $EquipmentBody
	build_shell("Inventory", _main_body, true)
	# The Equipment view shares the card; the header tabs swap the two bodies.
	_equipment_body.get_parent().remove_child(_equipment_body)
	content.add_child(_equipment_body)
	_build_view_tabs()
	_apply_blur_backdrop()
	_build_wallet()
	detail_icon.texture = null
	_detail_pixel = PixelIcon.mount(detail_icon)

	_build_rail_tabs()
	_build_hint_bar()

	action_button.pressed.connect(_on_action_button_pressed)
	hotkey_button.pressed.connect(_on_hotkey_button_pressed)
	pin_button.pressed.connect(_on_pin_button_pressed)

	_connect_equipment_signal()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _connect_equipment_signal())
	ClientState.input_changed.connect(func(_t: InputComponent.InputType): _update_pad_chips())

	_tab_filter = _session_tab
	_sync_tab_buttons()
	_clear_detail()
	fill_inventory()
	visibility_changed.connect(fill_inventory)
	# Refresh the bag live when ore is gathered while the menu is open.
	ClientState.gather_succeeded.connect(func(_result: Dictionary):
		if visible:
			fill_inventory())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"menu_tab_prev") and _main_body.visible:
		get_viewport().set_input_as_handled()
		_cycle_tab(-1)
	elif event.is_action_pressed(&"menu_tab_next") and _main_body.visible:
		get_viewport().set_input_as_handled()
		_cycle_tab(1)
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()


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


# --- Bag | Equipment view tabs (shell header center) ---

func _build_view_tabs() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for view: Array in [["Bag", &"bag"], ["Equipment", &"equipment"]]:
		var button: Button = Button.new()
		button.text = view[0]
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"FlatButton"
		button.custom_minimum_size = Vector2(110, 34)
		button.pressed.connect(_set_view.bind(StringName(view[1])))
		header_center.add_child(button)
		_view_tabs[view[1]] = button
	_view_tabs[&"bag"].set_pressed_no_signal(true)


func _set_view(view: StringName) -> void:
	_main_body.visible = view == &"bag"
	_equipment_body.visible = view == &"equipment"
	for key: StringName in _view_tabs:
		_view_tabs[key].set_pressed_no_signal(key == view)


# --- Category rail ---

func _build_rail_tabs() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for tab: Array in RAIL_TABS:
		var button: Button = Button.new()
		button.text = tab[0]
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"FlatButton"
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_tab.bind(int(tab[1])))
		if int(tab[1]) in DYNAMIC_TABS:
			button.visible = false # shown by _update_dynamic_tabs when such an item is held
		rail_tabs.add_child(button)
		_tab_buttons.append(button)
	_sync_tab_buttons()
	_update_pad_chips()


func _set_tab(filter: int) -> void:
	_tab_filter = filter
	_session_tab = filter
	_sync_tab_buttons()
	_rebuild_grid()


## Cycle through the visible rail tabs (pad LB/RB).
func _cycle_tab(direction: int) -> void:
	var visible_tabs: Array[int] = []
	for i: int in RAIL_TABS.size():
		if _tab_buttons[i].visible:
			visible_tabs.append(i)
	if visible_tabs.is_empty():
		return
	var current: int = 0
	for idx: int in visible_tabs.size():
		if int(RAIL_TABS[visible_tabs[idx]][1]) == _tab_filter:
			current = idx
	var next: int = visible_tabs[(current + direction + visible_tabs.size()) % visible_tabs.size()]
	_set_tab(int(RAIL_TABS[next][1]))


func _sync_tab_buttons() -> void:
	# set_pressed_no_signal bypasses the ButtonGroup — sync every tab.
	for i: int in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(int(RAIL_TABS[i][1]) == _tab_filter)


func _update_pad_chips() -> void:
	var pad: bool = ClientState.input_type == InputComponent.InputType.GAMEPAD
	lb_chip.visible = pad
	rb_chip.visible = pad


func _build_hint_bar() -> void:
	hint_bar = InputHintBar.new()
	hint_bar.set_hints({
		InputComponent.InputType.MOUSE_KEYBOARD: [["Esc", "Close"]],
		InputComponent.InputType.GAMEPAD: [["LB/RB", "Category"], ["B", "Close"]],
	})
	# Bottom of the LEFT column — the detail column keeps its full height, and
	# on touch (no hints) the freed row goes back to the grid.
	left_col.add_child(hint_bar)


## Same frosted-glass backdrop as the settings menu (owner comparing looks).
func _apply_blur_backdrop() -> void:
	var blur: ShaderMaterial = ShaderMaterial.new()
	blur.shader = load("res://source/client/ui/shared/menu_blur_backdrop.gdshader")
	blur.set_shader_parameter(&"blur_lod", 2.5)
	blur.set_shader_parameter(&"dim_color", Color(0.073365234, 0.08239203, 0.122337736, 0.55))
	backdrop.material = blur


# --- Bag data + grid ---

func fill_inventory() -> void:
	if _filling:
		_refill_queued = true
		return
	_filling = true
	var result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	_filling = false
	if _refill_queued:
		_refill_queued = false
		fill_inventory()
		return
	if result[1] != OK:
		fill_inventory()
		return

	_inventory = result[0]
	_set_wallet(Inventory.count(_inventory, _gold_id))
	_update_dynamic_tabs()
	_rebuild_grid()


## Favorites/Others/Quest tabs only exist while a matching item is held.
func _update_dynamic_tabs() -> void:
	var held: Dictionary = {}
	for tab: int in DYNAMIC_TABS:
		held[tab] = false
	for slot_uid_key in _inventory:
		var data: Dictionary = _inventory[slot_uid_key]
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(data.get("id", 0))) as Item
		if item == null or item.is_currency:
			continue
		if held.has(item.inventory_tab()):
			held[item.inventory_tab()] = true
		if data.get("p", false):
			held[TAB_FAVORITES] = true
	for i: int in RAIL_TABS.size():
		var filter: int = int(RAIL_TABS[i][1])
		if not held.has(filter):
			continue
		_tab_buttons[i].visible = held[filter]
		if not held[filter] and _tab_filter == filter:
			_set_tab(Item.InventoryTab.WEAPON)


func _rebuild_grid() -> void:
	for child: Node in section_list.get_children():
		child.queue_free()
	_tiles = []

	var sections: Dictionary = {}
	for entry: Dictionary in _collect_entries():
		var key: StringName = entry.group
		if not sections.has(key):
			sections[key] = []
		sections[key].append(entry)

	# Known groups render in GROUPS order; unknown group keys (a future weapon
	# category not listed yet) still render, appended alphabetically.
	var ordered_keys: Array = []
	for group: Array in GROUPS:
		ordered_keys.append(group[0])
	var extra_keys: Array = sections.keys().filter(func(k: StringName) -> bool: return not k in ordered_keys)
	extra_keys.sort()
	for key: StringName in ordered_keys + extra_keys:
		if not sections.has(key):
			continue
		var entries: Array = sections[key]
		entries.sort_custom(_entry_less_than)
		section_list.add_child(_make_section_header(_group_label(key)))
		var grid: GridContainer = GridContainer.new()
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override(&"h_separation", 6)
		grid.add_theme_constant_override(&"v_separation", 6)
		for entry: Dictionary in entries:
			var tile: Button = _make_bag_button(entry)
			grid.add_child(tile)
			_tiles.append([tile, entry])
		section_list.add_child(grid)

	_restore_selection()
	DragScroll.enable(bag_scroll) # touch/mouse drag-scroll the bag (flips fresh rows to PASS)


## Re-select the previously selected item after a rebuild (by bag uid, or by
## gear slot for equipped tiles); otherwise select the first tile so the
## detail column is never an empty box.
func _restore_selection() -> void:
	var target: Array = []
	for pair: Array in _tiles:
		var entry: Dictionary = pair[1]
		if _selected_item == null:
			break
		if _selected_slot_uid >= 0 and int(entry.uid) == _selected_slot_uid:
			target = pair
			break
		if _selected_slot_uid < 0 and not _selected_gear_slot.is_empty() and entry.slot_key == _selected_gear_slot:
			target = pair
			break
	if target.is_empty() and not _tiles.is_empty():
		target = _tiles[0]
	if target.is_empty():
		_clear_detail()
		return
	(target[0] as Button).set_pressed_no_signal(true)
	_on_entry_pressed(target[1])


func _group_label(key: StringName) -> String:
	for group: Array in GROUPS:
		if group[0] == key:
			return group[1]
	return String(key).capitalize()


## Everything the current tab shows: synthetic equipped-gear tiles first-in-
## group, then the bag. Each entry: item/id/uid/qty/pinned/equipped/slot_key/
## group/sort.
func _collect_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# item_id -> slot_key for equipped ids that are STILL in the bag (a weapon
	# mid-draw: the bag reconciles only when the draw lands). Those badge their
	# bag entry instead of getting a synthetic tile, so nothing duplicates.
	var equipped_in_bag: Dictionary = {}
	if ClientState.local_player != null and _tab_filter != TAB_FAVORITES:
		var values: Dictionary = ClientState.local_player.equipment_component.slots.values
		for slot_key: StringName in EQUIP_SLOT_KEYS:
			var item_id: int = int(values.get(slot_key, 0))
			if item_id <= 0:
				continue
			var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
			# Only true gear: a bag item riding the weapon slot (potion in
			# hand) already renders as its bag entry.
			if item == null or not item is GearItem:
				continue
			if not _passes_tab_value(item.inventory_tab()):
				continue
			if Inventory.has_item(_inventory, item_id):
				equipped_in_bag[item_id] = slot_key
				continue
			out.append({
				"item": item, "id": item_id, "uid": -1, "qty": 1,
				"pinned": false, "equipped": true, "slot_key": slot_key,
				"group": item.group_key(), "sort": item.sort_key(),
			})
	for slot_uid_key in _inventory:
		var data: Dictionary = _inventory[slot_uid_key]
		var item_id: int = int(data.get("id", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null or item.is_currency:
			continue
		var pinned: bool = bool(data.get("p", false))
		if _tab_filter == TAB_FAVORITES:
			if not pinned:
				continue
		elif not _passes_tab_value(item.inventory_tab()):
			continue
		var equipped_slot: StringName = equipped_in_bag.get(item_id, &"")
		if not equipped_slot.is_empty():
			equipped_in_bag.erase(item_id) # badge only one copy
		out.append({
			"item": item, "id": item_id, "uid": int(slot_uid_key),
			"qty": int(data.get("a", 1)), "pinned": pinned,
			"equipped": not equipped_slot.is_empty(), "slot_key": equipped_slot,
			"group": item.group_key(), "sort": item.sort_key(),
		})
	return out


func _passes_tab_value(tab: int) -> bool:
	return tab == _tab_filter


func _entry_less_than(a: Dictionary, b: Dictionary) -> bool:
	if a.equipped != b.equipped:
		return a.equipped # equipped tiles lead their section
	# The pinned section mixes groups, whose sort arrays aren't comparable
	# across groups — rank by group first, sort arrays only within one.
	var rank_a: int = _group_rank(a.group)
	var rank_b: int = _group_rank(b.group)
	if rank_a != rank_b:
		return rank_a < rank_b
	if a.sort != b.sort:
		return a.sort < b.sort
	return int(a.uid) < int(b.uid)


func _group_rank(key: StringName) -> int:
	for i: int in GROUPS.size():
		if GROUPS[i][0] == key:
			return i
	return GROUPS.size()


func _make_section_header(label_text: String) -> Label:
	var label: Label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_color_override(&"font_color", SECTION_HEADER_COLOR)
	return label


func _make_bag_button(entry: Dictionary) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(64, 64)
	button.clip_contents = true
	button.toggle_mode = true
	button.button_group = _tile_group
	var item: Item = entry.item
	PixelIcon.mount(button, item.item_icon)
	if int(entry.qty) > 1:
		var qty: Label = Label.new()
		qty.text = "x%d" % int(entry.qty)
		qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(qty)
	if entry.equipped:
		var badge: Label = Label.new()
		badge.text = "E"
		badge.add_theme_font_size_override(&"font_size", 12)
		badge.add_theme_color_override(&"font_color", EQUIPPED_BADGE_COLOR)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		# Tuck the badge inside the tile border instead of riding the edge.
		badge.offset_left -= 4
		badge.offset_right -= 4
		badge.offset_top += 2
		badge.offset_bottom += 2
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
	button.pressed.connect(_on_entry_pressed.bind(entry))
	# Double-click / double-tap = the primary action (equip/use/unequip).
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			_on_entry_pressed(entry)
			if not action_button.disabled:
				_on_action_button_pressed())
	return button


# --- Selection / detail column ---

func _on_entry_pressed(entry: Dictionary) -> void:
	_selected_item = entry.item
	_selected_item_id = int(entry.id)
	_selected_slot_uid = int(entry.uid)
	_selected_gear_slot = entry.slot_key
	_selected_pinned = bool(entry.pinned)
	PixelIcon.set_art(_detail_pixel, _selected_item.item_icon)
	detail_name.text = str(_selected_item.item_name)
	detail_description.text = ItemTooltip.body(_selected_item, _compare_target())

	if entry.equipped:
		action_button.text = "Unequip"
		action_button.disabled = false
		hotkey_button.disabled = true # bag items only — equipped gear isn't in the bag
		pin_button.disabled = true
		pin_button.text = "Favorite"
		return

	if _selected_item is GearItem:
		action_button.text = "Equip"
		action_button.disabled = false
	elif _selected_item is ConsumableItem:
		action_button.text = "Use"
		action_button.disabled = false
	elif _selected_item.holdable:
		action_button.text = "Hold"
		action_button.disabled = false
	else:
		action_button.text = "—"
		action_button.disabled = true
	# Anything you can equip / use / hold can sit on a quick slot.
	hotkey_button.disabled = action_button.disabled
	pin_button.disabled = false
	pin_button.text = "Unfavorite" if _selected_pinned else "Favorite"


## The equipped counterpart for stat deltas — only when the selection is bag
## gear (comparing an equipped piece to itself is noise).
func _compare_target() -> Item:
	if not _selected_gear_slot.is_empty() or not _selected_item is GearItem:
		return null
	if ClientState.local_player == null or _selected_item.slot == null:
		return null
	var equipped_id: int = int(ClientState.local_player.equipment_component.slots.values.get(_selected_item.slot.key, 0))
	if equipped_id <= 0 or equipped_id == _selected_item_id:
		return null
	var equipped: Item = ContentRegistryHub.load_by_id(&"items", equipped_id) as Item
	return equipped if equipped is GearItem else null


func _clear_detail() -> void:
	_selected_item = null
	_selected_item_id = 0
	_selected_slot_uid = -1
	_selected_gear_slot = &""
	_selected_pinned = false
	PixelIcon.set_art(_detail_pixel, null)
	detail_name.text = "Select an item"
	detail_description.text = ""
	action_button.disabled = true
	hotkey_button.disabled = true
	pin_button.disabled = true
	pin_button.text = "Favorite"


# --- Actions ---

func _on_action_button_pressed() -> void:
	# No _clear_detail on success: the refresh restores the selection (or the
	# first tile — for a fresh equip that IS the new badged tile).
	if not _selected_gear_slot.is_empty():
		var slot_key: StringName = _selected_gear_slot
		var unequip_result: Array = await Client.request_data_await(&"item.unequip", {"slot": slot_key}, InstanceClient.current.name)
		if not _surface_item_rejection(unequip_result):
			fill_inventory()
		return
	if _selected_item_id > 0 and (_selected_item is GearItem or _selected_item.holdable):
		var result: Array = await Client.request_data_await(&"item.equip", {"id": _selected_item_id}, InstanceClient.current.name)
		if not _surface_item_rejection(result):
			fill_inventory()


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


func _on_pin_button_pressed() -> void:
	if _selected_slot_uid < 0:
		return
	var pin: bool = not _selected_pinned
	var result: Array = await Client.request_data_await(
		&"item.pin", {"uid": _selected_slot_uid, "on": pin}, InstanceClient.current.name)
	if result[1] != OK or not bool(result[0].get("ok", false)):
		Toaster.toast("Couldn't update favorites.")
		return
	_selected_pinned = pin
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


func _set_wallet(amount: int) -> void:
	wallet_amount.text = str(amount)


# --- Equipment sync (badged tiles are rebuilt on any equipment change) ---

func _connect_equipment_signal() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return
	if not local_player.equipment_component.equipment_changed.is_connected(_on_equipment_changed):
		local_player.equipment_component.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(_slot_key: StringName, _item_id: int) -> void:
	# Re-FETCH, don't just rebuild: a weapon draw reconciles the bag only when
	# the draw lands, and rebuilding from the stale snapshot duplicated the
	# weapon (synthetic equipped tile + its not-yet-removed bag entry).
	if visible:
		fill_inventory()
