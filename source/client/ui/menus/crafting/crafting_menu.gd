extends MenuShell
## Crafting station UI — fullscreen master-detail on the shared MenuShell
## (mirrors shop_menu): the shell header carries category tabs (centre) and a
## profession chip + XP bar + gold balance (right); the left pane lists every
## recipe with a craftable/locked status glyph; the right pane pins the Craft
## button to the bottom with the station fee + predicted profession XP above it.
## Opened by the station NODE NAME (the server resolves the same station from
## the player's current map). Recipes render from the CraftingStationResource
## carried in the menu arg; only the craft itself is server-validated.

const COLOR_GOLD: Color = Color(1.0, 0.85, 0.45)
const COLOR_OK: Color = Color(0.5, 0.9, 0.5)
const COLOR_BAD: Color = Color(1.0, 0.5, 0.4)
const COLOR_MUTED: Color = Color(0.55, 0.58, 0.66)

## Owning CraftingStation node's name, sent with the craft request.
var _station_key: String
var _station: CraftingStationResource
## item_id -> owned count, from the latest inventory fetch.
var _owned: Dictionary[int, int]
var _golds: int
var _gold_id: int
var _profession_level: int = 1
var _profession_xp: int
var _profession_xp_to_next: int = 100
## Multiplier from xp-effect perks (Apprentice ranks), for the predicted gain.
var _xp_multiplier: float = 1.0
## Recipe indices in display order (sorted by gate, then name).
var _order: Array[int] = []
var _selected: int = -1
## Active category tab; empty when the station has a single category (no tabs).
var _tab: StringName = &""
var _has_tabs: bool = false

var _tab_buttons: Dictionary[StringName, Button] = {}
var _tab_group: ButtonGroup = ButtonGroup.new()
var _row_group: ButtonGroup = ButtonGroup.new()
var _prof_name_label: Label
var _prof_level_label: Label
var _xp_bar: ProgressBar
var _golds_label: Label

@onready var recipe_list: VBoxContainer = %RecipeList
@onready var list_scroll: ScrollContainer = %ScrollContainer
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name_label: Label = %DetailNameLabel
@onready var detail_slot_label: Label = %DetailSlotLabel
@onready var detail_owned_label: Label = %DetailOwnedLabel
@onready var stats_text: RichTextLabel = %StatsText
@onready var materials_list: VBoxContainer = %MaterialsList
@onready var gate_label: Label = %GateLabel
@onready var fee_label: Label = %FeeLabel
@onready var xp_label: Label = %XpLabel
@onready var craft_button: Button = %CraftButton


func _ready() -> void:
	_gold_id = Economy.gold_id()
	build_shell("Crafting", $Body, true)
	_build_header()
	craft_button.pressed.connect(_on_craft_pressed)
	visibility_changed.connect(_on_visibility_changed)


## Hand the crafting menu the station's catalog directly (rendered client-side)
## plus the node name the server resolves the station by.
func open(arg: Dictionary) -> void:
	_station_key = str(arg.get("key", ""))
	_station = arg.get("station") as CraftingStationResource
	if _station == null:
		hide()
		return
	set_title(_station.station_name if not _station.station_name.is_empty() else "Crafting")
	_prof_name_label.text = JobRegistry.display_name(_station.profession)
	_selected = -1
	_tab = &""
	_refresh()


func _on_visibility_changed() -> void:
	if visible and _station != null:
		_refresh()


## Profession chip + XP bar + gold balance, inserted left of the Close button.
func _build_header() -> void:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)

	_prof_name_label = Label.new()
	_prof_name_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	_prof_name_label.add_theme_font_size_override(&"font_size", 13)
	_prof_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_prof_name_label)

	_prof_level_label = Label.new()
	_prof_level_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	_prof_level_label.add_theme_font_size_override(&"font_size", 13)
	_prof_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_prof_level_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = &"XPBar"
	_xp_bar.custom_minimum_size = Vector2(110, 10)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	box.add_child(_xp_bar)

	var gold_icon: TextureRect = TextureRect.new()
	gold_icon.custom_minimum_size = Vector2(20, 20)
	gold_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var gold: Item = ContentRegistryHub.load_by_id(&"items", _gold_id)
	if gold != null:
		gold_icon.texture = gold.item_icon
	box.add_child(gold_icon)

	_golds_label = Label.new()
	_golds_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	_golds_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_golds_label)

	header_right.add_child(box)
	header_right.move_child(box, 0)


## Pulls inventory + profession progress, then rebuilds tabs, list, and detail.
func _refresh() -> void:
	var inv_result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if inv_result[1] == OK:
		_recompute_owned(inv_result[0])

	var skills_result: Array = await Client.request_data_await(&"skills.get", {}, InstanceClient.current.name)
	if skills_result[1] == OK:
		var skills: Dictionary = skills_result[0].get("skills", {})
		var entry: Dictionary = skills.get(String(_station.profession), {})
		_profession_level = int(entry.get("level", 1))
		_profession_xp = int(entry.get("xp", 0))
		_profession_xp_to_next = maxi(1, int(entry.get("xp_to_next", 100)))
		_xp_multiplier = _xp_multiplier_from(entry.get("choices", []))

	_update_header()
	_build_tabs()
	_build_list()
	_render_detail()


func _recompute_owned(inventory: Dictionary) -> void:
	_owned.clear()
	for slot_uid in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		if item_id > 0:
			_owned[item_id] = _owned.get(item_id, 0) + int(data.get("a", 0))
	_golds = _owned.get(_gold_id, 0)


## 1.0 + every rank of every xp-effect perk (Apprentice), for predicted gains.
func _xp_multiplier_from(choices: Variant) -> float:
	var mult: float = 1.0
	for choice: Variant in (choices if choices is Array else []):
		var c: Dictionary = choice
		if String(c.get("effect", "")) == "xp":
			mult += int(c.get("rank", 0)) * float(c.get("per_rank", 0.0))
	return mult


func _update_header() -> void:
	_prof_level_label.text = "Lv %d" % _profession_level
	_xp_bar.max_value = _profession_xp_to_next
	_xp_bar.value = _profession_xp
	_xp_bar.tooltip_text = "%d / %d xp" % [_profession_xp, _profession_xp_to_next]
	_golds_label.text = str(_golds)


# --- Category tabs -----------------------------------------------------------

## Which tab a recipe belongs to: materials (bars, cures), rings, or an armor
## line derived from the output's folder (metal stays plain "armor"; the
## Workbench splits into cloth / leather). No "all" tab on purpose — mixing
## categories interleaves unrelated rows (owner call 2026-07-02).
func _category(recipe: CraftingRecipe) -> StringName:
	if recipe.output_item is MaterialItem:
		return &"materials"
	var gear: GearItem = recipe.output_item as GearItem
	if gear != null and gear.slot != null and gear.slot.resource_path.get_file().begins_with("ring"):
		return &"rings"
	var path: String = recipe.output_item.resource_path
	if path.contains("/cloth/"):
		return &"cloth"
	if path.contains("/leather/"):
		return &"leather"
	return &"armor"


func _build_tabs() -> void:
	for child: Node in header_center.get_children():
		child.queue_free()
	_tab_buttons.clear()

	var present: Array[StringName] = []
	for recipe: CraftingRecipe in _station.recipes:
		if recipe == null or recipe.output_item == null:
			continue
		var cat: StringName = _category(recipe)
		if not present.has(cat):
			present.append(cat)
	# A lone category needs no tab bar at all (e.g. the Furnace).
	_has_tabs = present.size() > 1
	if not _has_tabs:
		_tab = &""
		return

	var tabs: Array[StringName] = []
	for cat: StringName in [&"armor", &"cloth", &"leather", &"rings", &"materials"]:
		if present.has(cat):
			tabs.append(cat)
	if not tabs.has(_tab):
		_tab = tabs[0]
	for cat: StringName in tabs:
		var tab: Button = Button.new()
		tab.text = String(cat).capitalize()
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.theme_type_variation = &"SectionTab"
		tab.custom_minimum_size = Vector2(0, 34)
		tab.button_pressed = (cat == _tab)
		tab.pressed.connect(_on_tab_pressed.bind(cat))
		header_center.add_child(tab)
		_tab_buttons[cat] = tab


func _on_tab_pressed(cat: StringName) -> void:
	_tab = cat
	_build_list()
	# Keep the selection if it survived the filter; otherwise pick the first row.
	if not _order.has(_selected):
		_selected = _order[0] if not _order.is_empty() else -1
		_build_list()
	_render_detail()


# --- Recipe list -------------------------------------------------------------

func _build_list() -> void:
	for child: Node in recipe_list.get_children():
		child.queue_free()

	_order.clear()
	for i: int in _station.recipes.size():
		var recipe: CraftingRecipe = _station.recipes[i]
		if recipe == null or recipe.output_item == null:
			continue
		if _has_tabs and _category(recipe) != _tab:
			continue
		_order.append(i)
	_order.sort_custom(func(a: int, b: int) -> bool:
		var ra: CraftingRecipe = _station.recipes[a]
		var rb: CraftingRecipe = _station.recipes[b]
		if ra.required_level != rb.required_level:
			return ra.required_level < rb.required_level
		return String(ra.output_item.item_name) < String(rb.output_item.item_name))

	if _selected == -1 and not _order.is_empty():
		_selected = _order[0]

	for i: int in _order:
		recipe_list.add_child(_make_row(i, _station.recipes[i]))
	DragScroll.enable(list_scroll)


func _make_row(index: int, recipe: CraftingRecipe) -> Button:
	var locked: bool = _profession_level < recipe.required_level
	var row: Button = Button.new()
	row.toggle_mode = true
	row.button_group = _row_group
	row.button_pressed = (index == _selected)
	row.custom_minimum_size = Vector2(0, 40)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.pressed.connect(_on_row_pressed.bind(index))

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8.0
	hbox.offset_right = -8.0
	hbox.add_theme_constant_override(&"separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = recipe.output_item.item_icon
	hbox.add_child(icon)

	var name_label: Label = Label.new()
	name_label.text = str(recipe.output_item.item_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_label)

	var status: Label = Label.new()
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if locked:
		status.text = "Lv %d" % recipe.required_level
		status.add_theme_color_override(&"font_color", COLOR_BAD)
		status.add_theme_font_size_override(&"font_size", 12)
		row.modulate = Color(1, 1, 1, 0.55)
	else:
		status.text = "●"
		status.add_theme_color_override(&"font_color", COLOR_OK if _has_ingredients(recipe) else COLOR_MUTED)
	hbox.add_child(status)
	return row


func _on_row_pressed(index: int) -> void:
	_selected = index
	_render_detail()


# --- Detail pane -------------------------------------------------------------

func _render_detail() -> void:
	for child: Node in materials_list.get_children():
		child.queue_free()
	if _selected < 0 or _selected >= _station.recipes.size():
		detail_name_label.text = "Select a recipe"
		detail_slot_label.text = ""
		detail_owned_label.text = ""
		detail_icon.texture = null
		stats_text.text = ""
		gate_label.text = ""
		fee_label.text = ""
		xp_label.text = ""
		craft_button.disabled = true
		craft_button.text = "Craft"
		return

	var recipe: CraftingRecipe = _station.recipes[_selected]
	var item: Item = recipe.output_item
	detail_icon.texture = item.item_icon
	detail_name_label.text = str(item.item_name)
	detail_slot_label.text = _slot_line(item)
	detail_owned_label.text = _owned_line(item)
	stats_text.text = ItemTooltip.body(item)

	var has_mats: bool = _has_ingredients(recipe)
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		materials_list.add_child(_make_material_row(ingredient))

	var meets_level: bool = _profession_level >= recipe.required_level
	if recipe.required_level > 0:
		gate_label.text = "%s Lv %d %s" % [
			JobRegistry.display_name(_station.profession),
			recipe.required_level,
			"met" if meets_level else "required",
		]
		gate_label.add_theme_color_override(&"font_color", COLOR_OK if meets_level else COLOR_BAD)
	else:
		gate_label.text = ""

	var fee: int = _station.craft_fee
	var can_pay: bool = _golds >= fee
	if fee > 0:
		fee_label.text = "Fee: %d gold" % fee
		fee_label.add_theme_color_override(&"font_color", COLOR_GOLD if can_pay else COLOR_BAD)
	else:
		fee_label.text = ""
	xp_label.text = "+%d %s xp" % [
		roundi(recipe.xp_reward * _xp_multiplier),
		JobRegistry.display_name(_station.profession),
	]

	craft_button.disabled = not (meets_level and has_mats and can_pay)
	if not meets_level:
		craft_button.text = "Requires Lv %d" % recipe.required_level
	elif not has_mats:
		craft_button.text = "Missing materials"
	elif not can_pay:
		craft_button.text = "Not enough gold"
	else:
		craft_button.text = "Craft"


## "Helmet · wearable at level N" for gear, "Material" for mats.
func _slot_line(item: Item) -> String:
	var gear: GearItem = item as GearItem
	if gear == null:
		return "Material"
	var slot_name: String = "Gear"
	if gear.slot != null:
		slot_name = gear.slot.resource_path.get_file().get_basename().capitalize()
	if gear.required_level > 0:
		return "%s · wearable at level %d" % [slot_name, gear.required_level]
	return slot_name


func _owned_line(item: Item) -> String:
	var item_id: int = int(item.get_meta(&"id", 0))
	var count: int = _owned.get(item_id, 0)
	var line: String = "In bag: %d" % count
	if item is GearItem and item_id in _equipped_ids():
		line += " · Equipped"
	return line


func _equipped_ids() -> Array:
	if ClientState.local_player == null:
		return []
	return ClientState.local_player.equipment_component.slots.values.values()


## One "name  have/need" row; gear ingredients read as "Consumes:" (ring upgrades).
func _make_material_row(ingredient: CraftIngredient) -> HBoxContainer:
	var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
	var have: int = _owned.get(ing_id, 0)
	var enough: bool = have >= ingredient.amount

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = ingredient.item.item_icon
	row.add_child(icon)

	var name_label: Label = Label.new()
	var prefix: String = "Consumes: " if ingredient.item is GearItem else ""
	name_label.text = prefix + str(ingredient.item.item_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", 13)
	row.add_child(name_label)

	var count_label: Label = Label.new()
	count_label.text = "%d / %d" % [have, ingredient.amount]
	count_label.add_theme_font_size_override(&"font_size", 13)
	count_label.add_theme_color_override(&"font_color", COLOR_OK if enough else COLOR_BAD)
	row.add_child(count_label)
	return row


func _has_ingredients(recipe: CraftingRecipe) -> bool:
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		if _owned.get(ing_id, 0) < ingredient.amount:
			return false
	return true


# --- Crafting ----------------------------------------------------------------

func _on_craft_pressed() -> void:
	if _selected < 0:
		return
	var recipe: CraftingRecipe = _station.recipes[_selected]
	var result: Array = await Client.request_data_await(
		&"craft.item",
		{"station_key": _station_key, "recipe": _selected},
		InstanceClient.current.name
	)
	if result[1] != OK or not result[0].get("ok", false):
		_toast_failure(result[0] if result[1] == OK else {})
		return

	var data: Dictionary = result[0]
	Toaster.toast("Crafted %d %s" % [int(data.get("amount", 1)), str(recipe.output_item.item_name)])
	if data.get("leveled_up", false):
		Toaster.toast("%s — Level %d!" % [JobRegistry.display_name(_station.profession), int(data.get("level", 1))])
	_refresh()


func _toast_failure(data: Dictionary) -> void:
	match String(data.get("reason", "")):
		"level":
			Toaster.toast("Requires level %d to craft this." % int(data.get("required_level", 0)))
		"ingredients":
			Toaster.toast("You don't have the ingredients.")
		"gold":
			Toaster.toast("Not enough gold for the station fee (%d)." % int(data.get("fee", 0)))
		_:
			Toaster.toast("Can't craft that right now.")
