extends Control
## Confirm dialog for an attribute re-spec — reached from an NPC's
## AttributeResetInteraction. Shows the gold fee; on confirm it fires the
## server-authoritative attribute.reset. Same compact card as the NPC dialogue.
##
## open() arg: the gold cost (int).


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(arg: Variant) -> void:
	for child: Node in get_children():
		child.queue_free()
	var cost: int = int(arg) if arg != null else 0

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.4)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 16)
	pad.add_theme_constant_override(&"margin_right", 16)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	pad.add_child(box)

	var title: Label = Label.new()
	title.text = "Respec attributes"
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	title.add_theme_font_size_override(&"font_size", 20)
	box.add_child(title)

	var body: Label = Label.new()
	body.text = "Refund all your spent attribute points so you can rebuild?\nThis costs %d gold." % cost
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", Color(0.85, 0.86, 0.92))
	box.add_child(body)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)

	var confirm: Button = Button.new()
	confirm.text = "Respec (%d g)" % cost
	confirm.custom_minimum_size = Vector2(150, 40)
	confirm.pressed.connect(_on_confirm)
	buttons.add_child(confirm)

	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(110, 40)
	cancel.pressed.connect(hide)
	buttons.add_child(cancel)


func _on_confirm() -> void:
	var result: Array = await Client.request_data_await(
		&"attribute.reset", {}, InstanceClient.current.name
	)
	hide()
	if result[1] != OK:
		return
	var data: Dictionary = result[0]
	if data.get("ok", false):
		Toaster.toast("Attributes reset — %d points to spend (Character menu)." % int(data.get("points", 0)))
		return
	match str(data.get("reason", "")):
		"gold":
			Toaster.toast("Not enough gold to respec.")
		"nothing":
			Toaster.toast("You haven't spent any attribute points yet.")
		_:
			Toaster.toast("Couldn't respec right now.")
