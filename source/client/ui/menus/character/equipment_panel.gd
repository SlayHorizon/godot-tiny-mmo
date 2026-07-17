extends HBoxContainer
## Character > Equipment tab: the paperdoll. Left card = the character's
## animated sprite with the gear slots orbiting it (helmet up top, weapon/torso
## at the sides, ring/boots low); right = summed gear stats ("what my set gives
## me") + the selected piece's detail with Unequip. Pure client view over the
## synced equipment slots — see docs/inventory.md for the bag-side story
## (badged tiles; this panel is the set OVERVIEW the bag deliberately lost).

const SLOT_TILE: Vector2 = Vector2(52, 52)
const FIGURE_BOX: Vector2 = Vector2(96, 120)
const FIGURE_SCALE: float = 3.0
const EMPTY_SLOT_DIM: Color = Color(1, 1, 1, 0.4)
const GOLD_TEXT: Color = Color(1.0, 0.95, 0.75)
const HEADER_GOLD: Color = Color(1, 0.9, 0.55)
const MUTED_TEXT: Color = Color(0.56, 0.6, 0.66)
## Display order of the paperdoll slots; resources carry placeholder icon +
## display name.
const SLOT_RES_PATHS: Dictionary = {
	&"helmet": "res://source/common/gameplay/items/item_slot/slots/helmet.tres",
	&"weapon": "res://source/common/gameplay/items/item_slot/slots/weapon.tres",
	&"torso": "res://source/common/gameplay/items/item_slot/slots/torso.tres",
	&"ring": "res://source/common/gameplay/items/item_slot/slots/ring.tres",
	&"boot": "res://source/common/gameplay/items/item_slot/slots/boot.tres",
}

var _slots: Dictionary[StringName, ItemSlot] = {}
var _slot_buttons: Dictionary[StringName, Button] = {}
var _slot_pixels: Dictionary[StringName, TextureRect] = {}
var _slot_group: ButtonGroup = ButtonGroup.new()
var _selected_slot: StringName

var _figure: AnimatedSprite2D
var _name_label: Label
var _level_label: Label
var _totals_text: RichTextLabel
var _piece_pixel: TextureRect
var _piece_name: Label
var _piece_sub: Label
var _piece_text: RichTextLabel
var _unequip_button: Button


func _ready() -> void:
	for slot_key: StringName in SLOT_RES_PATHS:
		_slots[slot_key] = load(SLOT_RES_PATHS[slot_key]) as ItemSlot
	_build_layout()
	visibility_changed.connect(_on_visibility_changed)
	ClientState.local_player_ready.connect(_on_local_player_ready)
	_hook_equipment()
	_refresh()


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


func _on_local_player_ready(_local_player: LocalPlayer) -> void:
	_hook_equipment()
	if visible:
		_refresh()


func _hook_equipment() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return
	if not local_player.equipment_component.equipment_changed.is_connected(_on_equipment_changed):
		local_player.equipment_component.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(_slot_key: StringName, _item_id: int) -> void:
	if visible:
		_refresh()


# --- Layout ---

func _build_layout() -> void:
	add_theme_constant_override(&"separation", 12)

	# Left card: the paperdoll.
	var doll_panel: PanelContainer = PanelContainer.new()
	doll_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(doll_panel)
	var doll_center: CenterContainer = CenterContainer.new()
	doll_panel.add_child(doll_center)
	var doll_row: HBoxContainer = HBoxContainer.new()
	doll_row.add_theme_constant_override(&"separation", 14)
	doll_center.add_child(doll_row)

	var left_col: VBoxContainer = _make_slot_column([&"weapon", &"ring"])
	doll_row.add_child(left_col)

	var center_col: VBoxContainer = VBoxContainer.new()
	center_col.alignment = BoxContainer.ALIGNMENT_CENTER
	center_col.add_theme_constant_override(&"separation", 8)
	doll_row.add_child(center_col)
	var helmet_center: CenterContainer = CenterContainer.new()
	helmet_center.add_child(_make_slot_button(&"helmet"))
	center_col.add_child(helmet_center)
	var figure_box: Control = Control.new()
	figure_box.custom_minimum_size = FIGURE_BOX
	center_col.add_child(figure_box)
	_figure = AnimatedSprite2D.new()
	_figure.position = FIGURE_BOX * 0.5
	_figure.scale = Vector2(FIGURE_SCALE, FIGURE_SCALE)
	_figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # crisp pixels
	figure_box.add_child(_figure)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override(&"font_color", GOLD_TEXT)
	center_col.add_child(_name_label)
	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override(&"font_size", 12)
	_level_label.add_theme_color_override(&"font_color", MUTED_TEXT)
	center_col.add_child(_level_label)

	var right_col: VBoxContainer = _make_slot_column([&"torso", &"boot"])
	doll_row.add_child(right_col)

	# Right side: totals card + selected piece card.
	var info_col: VBoxContainer = VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.size_flags_stretch_ratio = 1.15
	info_col.add_theme_constant_override(&"separation", 10)
	add_child(info_col)

	var totals_panel: PanelContainer = PanelContainer.new()
	info_col.add_child(totals_panel)
	var totals_pad: MarginContainer = _make_pad()
	totals_panel.add_child(totals_pad)
	var totals_box: VBoxContainer = VBoxContainer.new()
	totals_box.add_theme_constant_override(&"separation", 4)
	totals_pad.add_child(totals_box)
	var totals_title: Label = Label.new()
	totals_title.text = "Gear totals"
	totals_title.add_theme_color_override(&"font_color", HEADER_GOLD)
	totals_box.add_child(totals_title)
	_totals_text = RichTextLabel.new()
	_totals_text.bbcode_enabled = true
	_totals_text.fit_content = true
	totals_box.add_child(_totals_text)

	var piece_panel: PanelContainer = PanelContainer.new()
	piece_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_col.add_child(piece_panel)
	var piece_pad: MarginContainer = _make_pad()
	piece_panel.add_child(piece_pad)
	var piece_box: VBoxContainer = VBoxContainer.new()
	piece_box.add_theme_constant_override(&"separation", 6)
	piece_pad.add_child(piece_box)
	var piece_header: HBoxContainer = HBoxContainer.new()
	piece_header.add_theme_constant_override(&"separation", 8)
	piece_box.add_child(piece_header)
	var icon_host: TextureRect = TextureRect.new()
	icon_host.custom_minimum_size = Vector2(40, 40)
	icon_host.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_host.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	piece_header.add_child(icon_host)
	_piece_pixel = PixelIcon.mount(icon_host)
	var piece_names: VBoxContainer = VBoxContainer.new()
	piece_names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	piece_header.add_child(piece_names)
	_piece_name = Label.new()
	_piece_name.add_theme_color_override(&"font_color", GOLD_TEXT)
	piece_names.add_child(_piece_name)
	_piece_sub = Label.new()
	_piece_sub.add_theme_font_size_override(&"font_size", 12)
	_piece_sub.add_theme_color_override(&"font_color", MUTED_TEXT)
	piece_names.add_child(_piece_sub)
	_piece_text = RichTextLabel.new()
	_piece_text.bbcode_enabled = true
	_piece_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	piece_box.add_child(_piece_text)
	_unequip_button = Button.new()
	_unequip_button.text = "Unequip"
	_unequip_button.custom_minimum_size = Vector2(140, 38)
	_unequip_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_unequip_button.disabled = true
	_unequip_button.pressed.connect(_on_unequip_pressed)
	piece_box.add_child(_unequip_button)


func _make_pad() -> MarginContainer:
	var pad: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	return pad


func _make_slot_column(slot_keys: Array) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 14)
	for slot_key: StringName in slot_keys:
		column.add_child(_make_slot_button(slot_key))
	return column


func _make_slot_button(slot_key: StringName) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = SLOT_TILE
	button.clip_contents = true
	button.toggle_mode = true
	button.button_group = _slot_group
	button.tooltip_text = _slots[slot_key].display_name if _slots[slot_key] else String(slot_key)
	button.pressed.connect(_on_slot_pressed.bind(slot_key))
	_slot_buttons[slot_key] = button
	_slot_pixels[slot_key] = PixelIcon.mount(button)
	return button


# --- Data ---

func _refresh() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", local_player.skin_id) as SpriteFrames
	if frames != null:
		_figure.sprite_frames = frames
		_figure.play(&"idle")
	_name_label.text = str(local_player.display_name)
	_level_label.text = "Level %d" % ClientState.player_level

	var values: Dictionary = local_player.equipment_component.slots.values
	for slot_key: StringName in _slot_buttons:
		var item: Item = _slot_item(slot_key, values)
		if item != null:
			PixelIcon.set_art(_slot_pixels[slot_key], item.item_icon)
			_slot_buttons[slot_key].modulate = Color.WHITE
		else:
			var slot_res: ItemSlot = _slots[slot_key]
			PixelIcon.set_art(_slot_pixels[slot_key], slot_res.icon if slot_res else null)
			_slot_buttons[slot_key].modulate = EMPTY_SLOT_DIM

	_render_totals(values)
	if _selected_slot.is_empty():
		_select_first_filled(values)
	else:
		_render_piece(_selected_slot)


func _slot_item(slot_key: StringName, values: Dictionary) -> Item:
	var item_id: int = int(values.get(slot_key, 0))
	if item_id <= 0:
		return null
	return ContentRegistryHub.load_by_id(&"items", item_id) as Item


## Sum every equipped GearItem's modifiers and render them role-colored,
## offense -> defense -> utility, so the whole set reads as one build.
func _render_totals(values: Dictionary) -> void:
	var totals: Dictionary = {}
	for slot_key: StringName in _slot_buttons:
		var item: Item = _slot_item(slot_key, values)
		if not item is GearItem:
			continue # a bag item riding the hand (potion) adds no stats
		for modifier: StatModifier in item.base_modifiers:
			if modifier == null or is_zero_approx(modifier.value):
				continue
			var stat: StringName = StringName(modifier.stat_name)
			totals[stat] = float(totals.get(stat, 0.0)) + modifier.value
	if totals.is_empty():
		_totals_text.text = "[color=#9aa0aa]Nothing equipped yet.[/color]"
		return

	var stats: Array = totals.keys()
	stats.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _role_rank(a) < _role_rank(b))
	var lines: PackedStringArray = PackedStringArray()
	for stat: StringName in stats:
		lines.append("[color=#%s]%s %s[/color]" % [
			ItemTooltip.stat_color(stat), _format_value(totals[stat]), Stat.display_name(stat),
		])
	_totals_text.text = "\n".join(lines)


func _role_rank(stat: StringName) -> int:
	match ItemTooltip.STAT_ROLE.get(stat, &""):
		&"offense": return 0
		&"defense": return 1
		&"utility": return 2
	return 3


static func _format_value(value: float) -> String:
	return ("%+d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%+.1f" % value)


# --- Selection / piece detail ---

func _select_first_filled(values: Dictionary) -> void:
	for slot_key: StringName in _slot_buttons:
		if _slot_item(slot_key, values) != null:
			_slot_buttons[slot_key].set_pressed_no_signal(true)
			_render_piece(slot_key)
			return
	_render_piece(&"")


func _on_slot_pressed(slot_key: StringName) -> void:
	_render_piece(slot_key)


func _render_piece(slot_key: StringName) -> void:
	_selected_slot = slot_key
	var local_player: Player = ClientState.local_player
	var item: Item = null
	if local_player != null and not slot_key.is_empty():
		item = _slot_item(slot_key, local_player.equipment_component.slots.values)
	if item == null:
		PixelIcon.set_art(_piece_pixel, null)
		var slot_res: ItemSlot = _slots.get(slot_key)
		_piece_name.text = "Nothing equipped" if not slot_key.is_empty() else "Select a piece"
		_piece_sub.text = slot_res.display_name if slot_res else ""
		_piece_text.text = ""
		_unequip_button.disabled = true
		return
	PixelIcon.set_art(_piece_pixel, item.item_icon)
	_piece_name.text = str(item.item_name)
	_piece_sub.text = _piece_subtitle(item, slot_key)
	_piece_text.text = ItemTooltip.body(item)
	_unequip_button.disabled = false


## "Helmet · Iron set" for armor, "Weapon · Sword" for weapons; just the slot
## name for rings/relics (their group repeats the slot) and hand-held bag items.
func _piece_subtitle(item: Item, slot_key: StringName) -> String:
	var slot_res: ItemSlot = _slots.get(slot_key)
	var slot_name: String = slot_res.display_name if slot_res else String(slot_key).capitalize()
	if item is WeaponItem and not item.category.is_empty():
		return "%s · %s" % [slot_name, String(item.category).capitalize()]
	if item is GearItem and slot_key != &"ring" and slot_key != &"relic" and item.slot and item.slot.key != &"weapon":
		return "%s · %s set" % [slot_name, String(item.group_key()).capitalize()]
	return slot_name


func _on_unequip_pressed() -> void:
	if _selected_slot.is_empty():
		return
	var result: Array = await Client.request_data_await(
		&"item.unequip", {"slot": _selected_slot}, InstanceClient.current.name)
	var payload: Dictionary = result[0] if result[1] == OK and result[0] is Dictionary else {}
	if str(payload.get("reason", "")) == "in_combat":
		Toaster.toast("Can't change gear in combat (weapons only).")
		return
	_refresh()
