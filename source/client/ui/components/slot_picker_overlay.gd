class_name SlotPickerOverlay
extends ColorRect
## Modal "place X on which slot?" picker: a full-screen dim overlay that
## swallows every input, with a centered card listing one button per slot
## (label shows the slot's key + current occupant; picking an occupied slot
## replaces the occupant). Click the dim area or Cancel to close.
##
## Generic on purpose — used by the inventory hotkey assigner; the mastery
## panel's ability picker is the same pattern and can migrate here later.
## Parent it to a full-rect, non-container Control (a menu's scene root) so
## it covers the menu and dies with it.


## [param entries] one label per slot button ("Slot 1 (1) — Health Potion").
## [param on_pick] called with the chosen slot index; the overlay closes itself.
static func open(host: Control, title_text: String, entries: PackedStringArray, on_pick: Callable) -> SlotPickerOverlay:
	var overlay: SlotPickerOverlay = SlotPickerOverlay.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		var clicked: bool = (
			(event is InputEventMouseButton and event.pressed)
			or (event is InputEventScreenTouch and event.pressed)
		)
		if clicked:
			overlay.queue_free()
	)
	host.add_child(overlay)
	# AND_OFFSETS: the anchors-only preset keeps the fresh control's zero rect
	# (collapsed top-left) — same trap as the mastery picker hit.
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE # dim-area clicks reach the overlay (cancel)
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card: PanelContainer = PanelContainer.new()
	center.add_child(card)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 16)
	margin.add_theme_constant_override(&"margin_right", 16)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_bottom", 12)
	card.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 10)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for i: int in entries.size():
		var slot_button: Button = Button.new()
		slot_button.text = entries[i]
		slot_button.custom_minimum_size = Vector2(280, 44)
		slot_button.pressed.connect(func() -> void:
			overlay.queue_free()
			on_pick.call(i)
		)
		vbox.add_child(slot_button)

	vbox.add_child(HSeparator.new())
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 38)
	cancel.pressed.connect(overlay.queue_free)
	vbox.add_child(cancel)

	return overlay
