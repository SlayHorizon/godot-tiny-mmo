class_name MenuShell
extends Control
## Reusable full-window menu frame, built in code so any menu gets the same
## shell without duplicating the node tree. Matches the design in `docs/ui.md`:
## a dim backdrop, a responsive margin-anchored card, and a banner header with
## the title on the left, an optional centre slot (tabs), and a Close button on
## the right.
##
## Usage — a menu's root script does `extends MenuShell` and, in `_ready`:
## [codeblock]
## func _ready() -> void:
##     build_shell("Shop", $Body)   # reparents the authored body into the card
##     set_title(shop_name)         # later, once known
##     header_center.add_child(my_tab_bar)
## [/codeblock]
##
## Reparenting an authored body keeps its `unique_name_in_owner` (`%Foo`)
## lookups working — unique names resolve via the scene owner, not the parent,
## so moving nodes within the same scene is safe.

## Emitted when the Close button is pressed (the shell also hides itself).
signal close_requested

## The card content area — put the menu body here (build_shell does this for
## the `body` argument; add more children directly if needed). It's a
## borderless container: the Card already draws one frame, so menus add their
## own master/detail sub-panels inside without stacking a third border.
var content: MarginContainer
## Centre slot of the header bar — for tab bars / status labels.
var header_center: HBoxContainer
## Right slot of the header bar (holds Close) — add header-right widgets here.
var header_right: HBoxContainer

var _title_label: Label


## Builds the shell as children of `self`. If [param body] is given it's
## reparented into the card's content area. Call once from the menu's `_ready`.
func build_shell(title_text: String = "", body: Control = null, fullscreen: bool = false) -> void:
	var background: ColorRect = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.04, 0.05, 0.08, 0.5)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Content-heavy menus pass fullscreen=true for a thin outer inset (near edge-to-edge); small dialogs
	# keep a roomy floating margin. Per-menu opt-in so we convert them one at a time.
	var outer: int = 12 if fullscreen else 28
	var outer_tb: int = 12 if fullscreen else 22
	margin.add_theme_constant_override(&"margin_left", outer)
	margin.add_theme_constant_override(&"margin_right", outer)
	margin.add_theme_constant_override(&"margin_top", outer_tb)
	margin.add_theme_constant_override(&"margin_bottom", outer_tb)
	add_child(margin)

	var card: PanelContainer = PanelContainer.new()
	if fullscreen:
		# Full-screen menus drop the card frame — content sits straight on the dim full-rect backdrop
		# (world faint behind), not in an inset floating panel. The dim ColorRect IS the "background".
		card.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	margin.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 14)
	pad.add_theme_constant_override(&"margin_right", 14)
	pad.add_theme_constant_override(&"margin_top", 10)
	pad.add_theme_constant_override(&"margin_bottom", 12)
	card.add_child(pad)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	pad.add_child(root)

	# --- Header bar: title (left) / centre slot / close (right) ---
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	root.add_child(header)

	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	_title_label.add_theme_font_size_override(&"font_size", 20)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title_label)

	header_center = HBoxContainer.new()
	header_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	header_center.add_theme_constant_override(&"separation", 6)
	header.add_child(header_center)

	header_right = HBoxContainer.new()
	header_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_right.alignment = BoxContainer.ALIGNMENT_END
	header_right.add_theme_constant_override(&"separation", 8)
	header.add_child(header_right)

	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(72, 34)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(_on_close_pressed)
	header_right.add_child(close_button)

	root.add_child(HSeparator.new())

	content = MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	if body != null:
		if body.get_parent() != null:
			body.get_parent().remove_child(body)
		content.add_child(body)


func set_title(title_text: String) -> void:
	if _title_label != null:
		_title_label.text = title_text


func _on_close_pressed() -> void:
	close_requested.emit()
	hide()
