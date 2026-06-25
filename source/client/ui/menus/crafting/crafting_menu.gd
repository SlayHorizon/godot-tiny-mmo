extends Control
## Crafting station UI. Opened by name "crafting" with a station registry id.
## Lists the station's recipes with ingredient have/need and a Craft button. The recipe
## list is static client-side data (from the CraftingStationResource); only the craft
## itself is server-validated.

var _station_id: int
var _station: CraftingStationResource
## item_id -> owned count, from the latest inventory fetch.
var _owned: Dictionary[int, int]
## Current level in this station's profession (for the level-gate display); 1 if untrained.
var _profession_level: int = 1

@onready var title_label: Label = %TitleLabel
@onready var recipe_list: VBoxContainer = %RecipeList
@onready var recipe_scroll: ScrollContainer = $CenterContainer/Card/MarginContainer/VBoxContainer/ScrollContainer


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible and _station:
		_refresh()


func open(station_id: int) -> void:
	_station_id = station_id
	_station = CraftingStationResource.load_station(station_id)
	if _station == null:
		hide()
		return
	title_label.text = _station.station_name if not _station.station_name.is_empty() else "Crafting"
	_refresh()


## Pulls inventory counts + profession level, then rebuilds the recipe rows.
func _refresh() -> void:
	var inv_result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if inv_result[1] == OK:
		_recompute_owned(inv_result[0])

	var skills_result: Array = await Client.request_data_await(&"skills.get", {}, InstanceClient.current.name)
	if skills_result[1] == OK:
		var skills: Dictionary = skills_result[0].get("skills", {})
		var entry: Dictionary = skills.get(String(_station.profession), {})
		_profession_level = int(entry.get("level", 1))

	_build_list()


func _recompute_owned(inventory: Dictionary) -> void:
	_owned.clear()
	for slot_uid in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		if item_id > 0:
			_owned[item_id] = _owned.get(item_id, 0) + int(data.get("a", 0))


func _build_list() -> void:
	for child in recipe_list.get_children():
		child.queue_free()

	if _station == null or _station.recipes.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nothing to craft here."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		recipe_list.add_child(empty)
		return

	for i: int in _station.recipes.size():
		var recipe: CraftingRecipe = _station.recipes[i]
		if recipe == null or recipe.output_item == null:
			continue
		recipe_list.add_child(_make_recipe_row(i, recipe))
	DragScroll.enable(recipe_scroll) # touch/mouse drag-scroll the recipe list (flips fresh rows to PASS)


func _make_recipe_row(index: int, recipe: CraftingRecipe) -> PanelContainer:
	var meets_level: bool = _profession_level >= recipe.required_level
	var has_ingredients: bool = _has_ingredients(recipe)

	var panel: PanelContainer = PanelContainer.new()
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 10)
	margin.add_child(hbox)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.texture = recipe.output_item.item_icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(icon)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)
	hbox.add_child(info)

	var name_text: String = str(recipe.output_item.item_name)
	if recipe.output_amount > 1:
		name_text += " x%d" % recipe.output_amount
	var name_label: Label = Label.new()
	name_label.text = name_text
	info.add_child(name_label)

	var ingredients_label: RichTextLabel = RichTextLabel.new()
	ingredients_label.bbcode_enabled = true
	ingredients_label.fit_content = true
	ingredients_label.scroll_active = false
	ingredients_label.text = _ingredients_text(recipe)
	info.add_child(ingredients_label)

	if recipe.required_level > 0:
		var level_label: Label = Label.new()
		level_label.text = "Requires Lv %d" % recipe.required_level
		if not meets_level:
			level_label.add_theme_color_override(&"font_color", Color(1.0, 0.5, 0.4))
		info.add_child(level_label)

	var craft_button: Button = Button.new()
	craft_button.text = "Craft"
	craft_button.custom_minimum_size = Vector2(96, 44)
	craft_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	craft_button.disabled = not (meets_level and has_ingredients)
	craft_button.pressed.connect(_on_craft_pressed.bind(index, recipe))
	hbox.add_child(craft_button)

	return panel


## BBCode line listing each ingredient as "have/need", red when short.
func _ingredients_text(recipe: CraftingRecipe) -> String:
	var parts: PackedStringArray = []
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		var have: int = _owned.get(ing_id, 0)
		var name_str: String = str(ingredient.item.item_name)
		if have >= ingredient.amount:
			parts.append("%s %d/%d" % [name_str, have, ingredient.amount])
		else:
			parts.append("[color=#ff8070]%s %d/%d[/color]" % [name_str, have, ingredient.amount])
	return ", ".join(parts)


func _has_ingredients(recipe: CraftingRecipe) -> bool:
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		if _owned.get(ing_id, 0) < ingredient.amount:
			return false
	return true


func _on_craft_pressed(index: int, recipe: CraftingRecipe) -> void:
	var result: Array = await Client.request_data_await(
		&"craft.item",
		{"station": _station_id, "recipe": index},
		InstanceClient.current.name
	)
	if result[1] != OK or not result[0].get("ok", false):
		_toast_failure(result[0] if result[1] == OK else {})
		return

	var data: Dictionary = result[0]
	Toaster.toast("Crafted %d %s" % [int(data.get("amount", 1)), str(recipe.output_item.item_name)])
	if data.get("leveled_up", false):
		Toaster.toast("%s — Level %d!" % [String(data.get("profession", "")).capitalize(), int(data.get("level", 1))])
	_refresh()


func _toast_failure(data: Dictionary) -> void:
	match String(data.get("reason", "")):
		"level":
			Toaster.toast("Requires level %d to craft this." % int(data.get("required_level", 0)))
		"ingredients":
			Toaster.toast("You don't have the ingredients.")
		_:
			Toaster.toast("Can't craft that right now.")


func _on_close_button_pressed() -> void:
	hide()
