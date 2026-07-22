extends MenuShell
## Full-screen guild emblem catalog (wardrobe-style) — opened from the Guild
## Hall's Cosmetics tab and the guild menu's Settings via
## ClientState.open_menu_requested.emit(&"guild_emblems", guild_name).
## Replaced the Hall's popup once the catalog grew past four emblems
## (2026-07-19). Art + valid ids come from the shared GuildLogos catalog;
## buying goes through guild.logo.buy, equipping through guild.edit.

const COLOR_GOLD: Color = Color(1.0, 0.95, 0.75)
const COLOR_MUTED: Color = Color(0.75, 0.77, 0.83)

var _guild_name: String
## Last guild.get payload — the grid renders from this.
var _guild: Dictionary

var _funds_label: Label
var _grid_host: VBoxContainer


func _ready() -> void:
	build_shell("Guild Emblems", null, true)
	# Frosted-glass backdrop, matching the other guild surfaces.
	var blur: ShaderMaterial = ShaderMaterial.new()
	blur.shader = load("res://source/client/ui/shared/menu_blur_backdrop.gdshader")
	blur.set_shader_parameter(&"blur_lod", 2.5)
	blur.set_shader_parameter(&"dim_color", Color(0.073365234, 0.08239203, 0.122337736, 0.55))
	backdrop.material = blur

	_funds_label = Label.new()
	_funds_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	_funds_label.add_theme_font_size_override(&"font_size", 15)
	header_center.add_child(_funds_label)

	_grid_host = VBoxContainer.new()
	_grid_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_host.add_theme_constant_override(&"separation", 10)
	content.add_child(_grid_host)

	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


## Menu-launcher entry point: [param arg] is the guild name.
func open(arg: Variant) -> void:
	if arg is String and not (arg as String).is_empty():
		_guild_name = arg as String
	_refresh()


func _refresh() -> void:
	if _guild_name.is_empty():
		return
	Client.request_data(&"guild.get", _on_guild_loaded, {"q": _guild_name}, _inst())


func _on_guild_loaded(data: Dictionary) -> void:
	if not data.has("name"):
		Toaster.toast("Couldn't load the guild.")
		hide()
		return
	_guild = data
	set_title("Guild Emblems  ·  %s" % str(_guild.get("name", "?")))
	_funds_label.text = "%d  Guild Funds" % int(_guild.get("treasury", 0))
	_rebuild()


func _rebuild() -> void:
	for child: Node in _grid_host.get_children():
		child.queue_free()

	var blurb: Label = Label.new()
	blurb.text = "Shown on your banner, flags and guild page. The first emblem is free; unlock more with Guild Funds."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override(&"font_color", COLOR_MUTED)
	blurb.add_theme_font_size_override(&"font_size", 12)
	_grid_host.add_child(blurb)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_host.add_child(scroll)
	DragScroll.enable(scroll)

	var grid: HFlowContainer = HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	scroll.add_child(grid)

	var owned: Array = _guild.get("owned_logos", [0])
	var current: int = int(_guild.get("logo_id", 0))
	var cost: int = int(_guild.get("logo_cost", 250))
	var treasury: int = int(_guild.get("treasury", 0))
	var can_edit: bool = (int(_guild.get("permissions", 0)) & Guild.Permissions.EDIT) != 0
	for i: int in GuildLogos.count():
		grid.add_child(_emblem_tile(i, owned.has(i), i == current, cost, treasury, can_edit))

	if not can_edit:
		var note: Label = Label.new()
		note.text = "Only members with the Edit permission can spend Guild Funds."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override(&"font_color", COLOR_MUTED)
		note.add_theme_font_size_override(&"font_size", 11)
		_grid_host.add_child(note)


## One emblem tile: the art + its state button (Current / Use / Buy).
func _emblem_tile(logo_id: int, is_owned: bool, is_current: bool, cost: int, treasury: int, can_edit: bool) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(pad)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	pad.add_child(box)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(96, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = GuildLogos.texture(logo_id)
	icon.modulate = Color.WHITE if is_owned else Color(0.45, 0.45, 0.5)
	box.add_child(icon)

	var action: Button = Button.new()
	action.custom_minimum_size = Vector2(96, 32)
	if is_current:
		action.text = "Current"
		action.disabled = true
	elif is_owned:
		action.text = "Use"
		action.disabled = not can_edit
		action.pressed.connect(func() -> void: _use_emblem(logo_id))
	else:
		action.text = "Buy (%d)" % cost
		action.disabled = not can_edit or treasury < cost
		action.tooltip_text = "Not enough Guild Funds." if (can_edit and treasury < cost) else ""
		action.pressed.connect(func() -> void: _buy_emblem(logo_id))
	box.add_child(action)
	return panel


func _buy_emblem(logo_id: int) -> void:
	Client.request_data(&"guild.logo.buy", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't buy the emblem.")))
			return
		Toaster.toast("Emblem unlocked.")
		_refresh(),
		{"q": _guild_name, "logo_id": logo_id}, _inst())


func _use_emblem(logo_id: int) -> void:
	Client.request_data(&"guild.edit", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't change the emblem.")))
			return
		_refresh(),
		{"name": _guild_name, "logo_id": logo_id}, _inst())


func _inst() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current else ""
