class_name WelcomeScreen
extends Control
## One-time first-run welcome modal: a dim backdrop and a centered card with the alpha intro and a single
## dismiss button. Built in code, added by the HUD when the local "seen_welcome" flag is unset, and frees
## itself on dismiss. The same guidance lives in the Help menu for later. Edit WELCOME_TEXT to retune.


const WELCOME_TEXT: String = """This is a hard, sandbox MMORPG. You are free to do whatever you want, and you will find most of your footing on your own. That is by design.

If you want somewhere to start: step out of this cell and talk to the Hall Keeper. They can give you your first quest.

You can reopen this kind of guidance any time from the Help menu. Good luck."""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A first-run modal owns the screen: force it above the HUD and the chat (same UI CanvasLayer).
	z_index = 4096

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.6)
	add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(pad)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 16)
	pad.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Welcome to the Alpha"
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	vbox.add_child(title)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(416, 0)
	body.add_theme_constant_override(&"line_separation", 5)
	body.text = WELCOME_TEXT
	vbox.add_child(body)

	var got_it: Button = Button.new()
	got_it.text = "Got it"
	got_it.custom_minimum_size = Vector2(0, 40)
	got_it.pressed.connect(queue_free)
	vbox.add_child(got_it)
