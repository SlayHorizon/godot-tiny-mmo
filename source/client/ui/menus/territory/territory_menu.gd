extends MenuShell
## Territory panel — opened by clicking your own guild's flag in the world
## (TerritoryFlag._on_flag_clicked). Shows the flag's state and the defender
## garrison, with a Reinforce action (treasury-funded guard respawn). All data
## comes from the territory.info handler in one round-trip; the server gates
## every action again, this panel only reflects what it said.

const COLOR_GOLD: Color = Color(1.0, 0.95, 0.75)
const COLOR_MUTED: Color = Color(0.75, 0.77, 0.83)
const COLOR_GOOD: Color = Color(0.55, 0.85, 0.95)
const COLOR_BAD: Color = Color(0.95, 0.6, 0.55)

var _flag_id: int = -1
var _body: VBoxContainer


func _ready() -> void:
	build_shell("Territory", null, false)
	# The shell card spans the window; this panel is only a handful of rows, so
	# center a compact sub-card instead of stretching rows across the screen.
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 0)
	center.add_child(card)
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 8)
	pad.add_child(_body)


## Menu-launcher entry point (hud.display_menu): [param arg] is the flag_id.
func open(arg: Variant) -> void:
	_flag_id = int(arg)
	_refresh()


func _refresh() -> void:
	if _flag_id < 0 or InstanceClient.current == null:
		return
	Client.request_data(&"territory.info", _on_info, {"flag_id": _flag_id}, InstanceClient.current.name)


func _on_info(data: Dictionary) -> void:
	if not bool(data.get("ok", false)):
		Toaster.toast(str(data.get("message", "Couldn't read the territory.")))
		hide()
		return

	set_title(str(data.get("territory_name", "Territory")))
	for child: Node in _body.get_children():
		child.queue_free()

	var owner_name: String = str(data.get("owner_guild_name", ""))
	_body.add_child(_row("Held by", "[%s]" % owner_name if not owner_name.is_empty() else "Nobody", COLOR_GOLD))

	# Flag condition: full HP reads "Secure" instead of raw numbers.
	var hp: int = int(ceil(float(data.get("hp", 0))))
	var hp_max: int = int(float(data.get("hp_max", 1)))
	if hp >= hp_max:
		_body.add_child(_row("Flag", "Secure", COLOR_GOOD))
	else:
		_body.add_child(_row("Flag", "%d / %d HP" % [hp, hp_max], COLOR_BAD))

	var grace_ms: int = int(data.get("grace_until_ms_remaining", 0))
	if grace_ms > 0:
		@warning_ignore("integer_division")
		var secs: int = grace_ms / 1000
		@warning_ignore("integer_division")
		_body.add_child(_row("Immune", "%d:%02d remaining" % [secs / 60, secs % 60], COLOR_GOOD))

	# Garrison status + the Reinforce action.
	_body.add_child(HSeparator.new())
	var cap: int = int(data.get("defender_cap", 0))
	var alive: int = int(data.get("defenders_alive", 0))
	if not bool(data.get("defenders_enabled", true)):
		_body.add_child(_note("Defenders can't be stationed at this territory."))
	elif cap <= 0:
		_body.add_child(_note("No guards. Buy the Defenders upgrade in the Guild Hall to garrison your flags."))
	else:
		_body.add_child(_row("Guards", "%d / %d standing" % [alive, cap], COLOR_GOOD if alive >= cap else COLOR_BAD))
		var missing: int = int(data.get("missing", 0))
		if missing > 0 and bool(data.get("is_owner_member", false)):
			var cost: int = int(data.get("reinforce_cost", 0))
			var reinforce: Button = Button.new()
			reinforce.text = "Reinforce  (%d funds)" % cost
			reinforce.custom_minimum_size = Vector2(0, 40)
			reinforce.disabled = not bool(data.get("can_reinforce", false))
			if reinforce.disabled:
				reinforce.tooltip_text = (
					"Not enough Guild Funds." if int(data.get("treasury", 0)) < cost
					else "Needs the Edit permission."
				)
			reinforce.pressed.connect(_on_reinforce_pressed)
			_body.add_child(reinforce)
			_body.add_child(_note("Treasury: %d funds" % int(data.get("treasury", 0))))

	show()


func _on_reinforce_pressed() -> void:
	Client.request_data(&"guild.defenders.reinforce", func(data: Dictionary) -> void:
		if not bool(data.get("ok", false)):
			Toaster.toast(str(data.get("message", "Couldn't reinforce.")))
		else:
			Toaster.toast("Guards reinforced: %d / %d standing." % [
				int(data.get("defenders_alive", 0)), int(data.get("defender_cap", 0))])
		_refresh(),
		{"flag_id": _flag_id}, InstanceClient.current.name)


func _row(label_text: String, value_text: String, value_color: Color) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(90, 0)
	label.add_theme_color_override(&"font_color", COLOR_MUTED)
	row.add_child(label)
	var value: Label = Label.new()
	value.text = value_text
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_color_override(&"font_color", value_color)
	row.add_child(value)
	return row


func _note(text: String) -> Label:
	var note: Label = Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	note.add_theme_color_override(&"font_color", COLOR_MUTED)
	note.add_theme_font_size_override(&"font_size", 12)
	return note
