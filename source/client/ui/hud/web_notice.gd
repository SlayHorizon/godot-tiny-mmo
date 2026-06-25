class_name WebNotice
extends Control
## One-time, web-only notice: tells browser players this is the lighter build (some effects
## such as weather are disabled for performance) and points them at the downloadable version
## for the full experience. Added once by the HUD via a client "seen_web_notice" flag, and
## frees itself on dismiss. Edit NOTICE_TEXT + DOWNLOAD_URL below to retune the copy / target.


## Where "Get the full version" sends the player. Opened in a new browser tab on web via
## OS.shell_open. TODO: point this at your itch.io download page if you'd rather link there.
const DOWNLOAD_URL: String = "https://ekoniaonline.com"

const NOTICE_TEXT: String = """You're playing the browser version, which runs lighter for compatibility. Some effects like weather are turned off and the performance is capped.

For the full experience, with all effects and smoother performance, grab the downloadable build."""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Own the screen above the HUD and chat (same UI CanvasLayer), like the welcome modal.
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
	title.text = "Playing on the web"
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	vbox.add_child(title)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(416, 0)
	body.add_theme_constant_override(&"line_separation", 5)
	body.text = NOTICE_TEXT
	vbox.add_child(body)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(buttons)

	var later: Button = Button.new()
	later.text = "Continue on web"
	later.custom_minimum_size = Vector2(0, 40)
	later.pressed.connect(queue_free)
	buttons.add_child(later)

	var download: Button = Button.new()
	download.text = "Get the full version"
	download.custom_minimum_size = Vector2(0, 40)
	download.pressed.connect(func() -> void:
		OS.shell_open(DOWNLOAD_URL)
		queue_free())
	buttons.add_child(download)
