extends MenuShell
## Full-screen Guild Hall on MenuShell (replaces the cramped modal that lived
## inside guild_menu — owner call 2026-07-19, same pattern as the mastery tree
## opening from the character menu). Opened via
## ClientState.open_menu_requested.emit(&"guild_hall", guild_name).
##
## Layout: left column = treasury (balance, caps, deposit) + territories with
## live guard counts; right column = the active section, tabbed in the header:
## Upgrades (buy levels, Now/Next effect lines) and Cosmetics (emblem catalog,
## default free + fund-priced unlocks).

## Mirrors guild_menu.LOGOS — keep both in sync with the logo assets.
const LOGOS: Array[Texture2D] = [
	preload("res://assets/sprites/guild_logos/wyvern.png"),
	preload("res://assets/sprites/guild_logos/kawaii_skull.png"),
	preload("res://assets/sprites/guild_logos/cute_crown.png"),
	preload("res://assets/sprites/guild_logos/cute_fish.png"),
]

const COLOR_GOLD: Color = Color(1.0, 0.95, 0.75)
const COLOR_SECTION: Color = Color(1.0, 0.85, 0.5)
const COLOR_MUTED: Color = Color(0.75, 0.77, 0.83)

var _guild_name: String
## Last guild.get payload — every view renders from this.
var _guild: Dictionary
var _section: String = "upgrades"

var _tab_buttons: Dictionary
var _left_host: VBoxContainer
var _right_host: VBoxContainer


func _ready() -> void:
	build_shell("Guild Hall", null, true)
	# Frosted-glass backdrop, matching guild_menu / settings / inventory.
	var blur: ShaderMaterial = ShaderMaterial.new()
	blur.shader = load("res://source/client/ui/shared/menu_blur_backdrop.gdshader")
	blur.set_shader_parameter(&"blur_lod", 2.5)
	blur.set_shader_parameter(&"dim_color", Color(0.073365234, 0.08239203, 0.122337736, 0.55))
	backdrop.material = blur

	for s: Array in [["upgrades", "Upgrades"], ["cosmetics", "Cosmetics"]]:
		var btn: Button = Button.new()
		btn.text = s[1]
		btn.theme_type_variation = &"SectionTab"
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(120, 32)
		btn.pressed.connect(_select_section.bind(str(s[0])))
		header_center.add_child(btn)
		_tab_buttons[s[0]] = btn

	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override(&"separation", 18)
	content.add_child(cols)

	# No column panels — frosted style: content sits directly on the blurred
	# backdrop, a thin divider separates treasury from the tabbed section.
	# MarginContainers (not plain Controls) so the scroll children auto-fill.
	var left_panel: MarginContainer = MarginContainer.new()
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.custom_minimum_size = Vector2(300, 0)
	cols.add_child(left_panel)
	_left_host = _padded_scroll(left_panel)

	cols.add_child(VSeparator.new())

	var right_panel: MarginContainer = MarginContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right_panel)
	_right_host = _padded_scroll(right_panel)

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
	set_title("Guild Hall  ·  %s" % str(_guild.get("name", "?")))
	_rebuild()


func _select_section(section: String) -> void:
	_section = section
	_rebuild()


func _rebuild() -> void:
	for key: String in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = (key == _section)
	_build_left()
	match _section:
		"cosmetics":
			_build_cosmetics(_right_host)
		_:
			_build_upgrades(_right_host)


# ---------------------------------------------------------------------------
# Left column — treasury, deposit, territories
# ---------------------------------------------------------------------------

func _build_left() -> void:
	for child: Node in _left_host.get_children():
		child.queue_free()

	_left_host.add_child(_section_header("Treasury"))
	var balance: Label = Label.new()
	balance.text = "%d  Guild Funds" % int(_guild.get("treasury", 0))
	balance.add_theme_font_size_override(&"font_size", 24)
	balance.add_theme_color_override(&"font_color", COLOR_GOLD)
	_left_host.add_child(balance)

	var caps: Label = Label.new()
	caps.text = "Tag cap: %d online\nRoster: %d / %d" % [
		int(_guild.get("tag_cap", 15)), int(_guild.get("size", 0)), int(_guild.get("max_members", 25))]
	caps.add_theme_color_override(&"font_color", COLOR_MUTED)
	caps.add_theme_font_size_override(&"font_size", 12)
	_left_host.add_child(caps)

	_left_host.add_child(HSeparator.new())
	_left_host.add_child(_section_header("Deposit gold"))
	var gold: int = int(_guild.get("viewer_gold", 0))
	var gold_label: Label = Label.new()
	gold_label.text = "You have %d gold" % gold
	gold_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	gold_label.add_theme_font_size_override(&"font_size", 12)
	_left_host.add_child(gold_label)

	var dep_row: HBoxContainer = HBoxContainer.new()
	dep_row.add_theme_constant_override(&"separation", 8)
	_left_host.add_child(dep_row)
	var amount_field: SpinBox = SpinBox.new()
	amount_field.min_value = 0
	amount_field.max_value = maxi(gold, 0)
	amount_field.value = mini(100, gold)
	amount_field.step = 10
	amount_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dep_row.add_child(amount_field)
	var deposit: Button = Button.new()
	deposit.text = "Deposit"
	deposit.disabled = gold <= 0
	deposit.pressed.connect(func() -> void:
		_deposit(int(amount_field.value)))
	dep_row.add_child(deposit)

	# Held territories with live guard counts — what the Defender upgrades are
	# actually doing right now. Reinforcing happens AT the flag (click it).
	_left_host.add_child(HSeparator.new())
	_left_host.add_child(_section_header("Territories"))
	var territories: Array = _guild.get("territories", [])
	if territories.is_empty():
		var none: Label = Label.new()
		none.text = "No territory held."
		none.add_theme_color_override(&"font_color", COLOR_MUTED)
		none.add_theme_font_size_override(&"font_size", 12)
		_left_host.add_child(none)
	else:
		for territory: Dictionary in territories:
			var line: Label = Label.new()
			var text: String = str(territory.get("name", "?"))
			var cap: int = int(territory.get("defender_cap", 0))
			if cap > 0:
				text += "   ·   %d / %d guards" % [int(territory.get("defenders", 0)), cap]
			line.text = text
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_theme_font_size_override(&"font_size", 12)
			_left_host.add_child(line)
		var hint: Label = Label.new()
		hint.text = "Click a flag in the world to inspect or reinforce it."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override(&"font_color", COLOR_MUTED)
		hint.add_theme_font_size_override(&"font_size", 11)
		_left_host.add_child(hint)


# ---------------------------------------------------------------------------
# Upgrades section
# ---------------------------------------------------------------------------

func _build_upgrades(host: VBoxContainer) -> void:
	for child: Node in host.get_children():
		child.queue_free()
	host.add_child(_section_header("Upgrades"))

	var can_upgrade: bool = _can_edit()
	var treasury: int = int(_guild.get("treasury", 0))
	for up: Dictionary in _guild.get("hall_upgrades", []):
		host.add_child(_upgrade_row(up, can_upgrade, treasury))

	if not can_upgrade:
		host.add_child(_perm_note())


## One upgrade row: name + level, current/next effect values, description, Buy.
func _upgrade_row(up: Dictionary, can_upgrade: bool, treasury: int) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(pad)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	pad.add_child(row)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var title: Label = Label.new()
	title.text = "%s   (Lv %d / %d)" % [
		str(up.get("name", "?")), int(up.get("level", 0)), int(up.get("max_level", 0))]
	title.add_theme_color_override(&"font_color", COLOR_GOLD)
	info.add_child(title)

	var now_text: String = str(up.get("effect_now", ""))
	var next_text: String = str(up.get("effect_next", ""))
	if not now_text.is_empty():
		var effect: Label = Label.new()
		effect.text = "Now: %s" % now_text \
			+ ("      Next: %s" % next_text if not next_text.is_empty() else "")
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.add_theme_color_override(&"font_color", COLOR_SECTION)
		effect.add_theme_font_size_override(&"font_size", 11)
		info.add_child(effect)

	var desc: Label = Label.new()
	desc.text = str(up.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override(&"font_color", COLOR_MUTED)
	desc.add_theme_font_size_override(&"font_size", 11)
	info.add_child(desc)

	var buy: Button = Button.new()
	buy.custom_minimum_size = Vector2(120, 36)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var next_cost: int = int(up.get("next_cost", -1))
	if next_cost < 0:
		buy.text = "Maxed"
		buy.disabled = true
	else:
		buy.text = "Buy (%d)" % next_cost
		buy.disabled = not can_upgrade or treasury < next_cost
		buy.tooltip_text = "Not enough Guild Funds." if (can_upgrade and treasury < next_cost) else ""
		var uid: String = str(up.get("id", ""))
		buy.pressed.connect(func() -> void: _buy_upgrade(uid))
	row.add_child(buy)
	return panel


# ---------------------------------------------------------------------------
# Cosmetics section — emblem catalog (default free, others fund-priced)
# ---------------------------------------------------------------------------

func _build_cosmetics(host: VBoxContainer) -> void:
	for child: Node in host.get_children():
		child.queue_free()
	host.add_child(_section_header("Guild Emblem"))

	var blurb: Label = Label.new()
	blurb.text = "Shown on your banner, flags and guild page. The first emblem is free; unlock more with Guild Funds."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override(&"font_color", COLOR_MUTED)
	blurb.add_theme_font_size_override(&"font_size", 12)
	host.add_child(blurb)

	var owned: Array = _guild.get("owned_logos", [0])
	var current: int = int(_guild.get("logo_id", 0))
	var cost: int = int(_guild.get("logo_cost", 250))
	var treasury: int = int(_guild.get("treasury", 0))
	var can_edit: bool = _can_edit()

	var grid: HFlowContainer = HFlowContainer.new()
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	host.add_child(grid)

	for i: int in LOGOS.size():
		grid.add_child(_logo_tile(i, owned.has(i), i == current, cost, treasury, can_edit))

	if not can_edit:
		host.add_child(_perm_note())


## One emblem tile: the logo + its state button (Current / Use / Buy).
func _logo_tile(logo_id: int, is_owned: bool, is_current: bool, cost: int, treasury: int, can_edit: bool) -> Control:
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
	icon.texture = LOGOS[logo_id]
	icon.modulate = Color.WHITE if is_owned else Color(0.45, 0.45, 0.5)
	box.add_child(icon)

	var action: Button = Button.new()
	action.custom_minimum_size = Vector2(120, 34)
	if is_current:
		action.text = "Current"
		action.disabled = true
	elif is_owned:
		action.text = "Use"
		action.disabled = not can_edit
		action.pressed.connect(func() -> void: _use_logo(logo_id))
	else:
		action.text = "Buy (%d)" % cost
		action.disabled = not can_edit or treasury < cost
		action.tooltip_text = "Not enough Guild Funds." if (can_edit and treasury < cost) else ""
		action.pressed.connect(func() -> void: _buy_logo(logo_id))
	box.add_child(action)
	return panel


# ---------------------------------------------------------------------------
# Actions — every success re-fetches guild.get and rebuilds in place
# ---------------------------------------------------------------------------

func _buy_upgrade(upgrade_id: String) -> void:
	if upgrade_id.is_empty():
		return
	Client.request_data(&"guild.hall.upgrade", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't upgrade.")))
			return
		Toaster.toast("%s upgraded to Lv %d." % [
			str(data.get("upgrade", "Upgrade")), int(data.get("level", 0))])
		_refresh(),
		{"id": int(_guild.get("id", 0)), "upgrade": upgrade_id}, _inst())


func _deposit(amount: int) -> void:
	if amount <= 0:
		return
	Client.request_data(&"guild.treasury.deposit", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't deposit.")))
			return
		Toaster.toast("Deposited %d to the treasury." % int(data.get("deposited", amount)))
		_refresh(),
		{"id": int(_guild.get("id", 0)), "amount": amount}, _inst())


func _buy_logo(logo_id: int) -> void:
	Client.request_data(&"guild.logo.buy", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't buy the emblem.")))
			return
		Toaster.toast("Emblem unlocked.")
		_refresh(),
		{"q": _guild_name, "logo_id": logo_id}, _inst())


func _use_logo(logo_id: int) -> void:
	Client.request_data(&"guild.edit", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't change the emblem.")))
			return
		_refresh(),
		{"name": _guild_name, "logo_id": logo_id}, _inst())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _can_edit() -> bool:
	return (int(_guild.get("permissions", 0)) & Guild.Permissions.EDIT) != 0


func _perm_note() -> Label:
	var note: Label = Label.new()
	note.text = "Only members with the Edit permission can spend Guild Funds."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override(&"font_color", COLOR_MUTED)
	note.add_theme_font_size_override(&"font_size", 11)
	return note


func _padded_scroll(parent: Node) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 8)
	margin.add_child(box)
	DragScroll.enable(scroll)
	return box


func _section_header(text: String) -> Label:
	var header: Label = Label.new()
	header.text = text
	header.add_theme_font_size_override(&"font_size", 13)
	header.add_theme_color_override(&"font_color", COLOR_SECTION)
	return header


func _inst() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current else ""
