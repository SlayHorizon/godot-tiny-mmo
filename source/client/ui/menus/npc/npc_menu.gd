extends Control
## NPC dialogue — Undertale / Zelda-style. The NPC name + text sit in a fixed box
## pinned to the bottom-left; the options are a vertical, touch-friendly list on
## the right (kept OUT of the box so it never resizes/jitters). "Talk" options play
## their lore lines inline with a typewriter reveal — click to skip to the full
## line, click again to advance. Routing options hand off to their menus.
##
## Text is a RichTextLabel with bbcode, so lines can use [color], [wave], [shake]…
## No backdrop: real-time MMO, the world stays visible + playable; only the box +
## buttons eat clicks.
##
## open() arg: {
##   "name", "greeting",
##   "entries": [ {label, icon, menu, arg}  (routes out)
##              | {label, icon, lines}      (plays inline) ],
## }

## Reveal speed for the typewriter (visible characters per second).
const TYPE_CPS: float = 45.0
## Uniform touch-target height for the option buttons.
const BUTTON_HEIGHT: float = 46.0

var _data: Dictionary
var _lines: Array = []
var _line_index: int = 0
var _typing: bool = false

var _box: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _options: VBoxContainer
var _type_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Let clicks outside the box/buttons reach the world (movement etc.).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func open(arg: Variant) -> void:
	_data = arg if arg is Dictionary else {}
	for child: Node in get_children():
		child.queue_free()
	_build()
	_show_options()


func _build() -> void:
	# Text box: bottom, spanning the left side (room for options on the right).
	var box: PanelContainer = PanelContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 40
	box.offset_right = -300
	box.offset_top = -132
	box.offset_bottom = -28
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN # taller text grows the box UP; bottom stays put
	add_child(box)
	_box = box

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 18)
	pad.add_theme_constant_override(&"margin_right", 18)
	pad.add_theme_constant_override(&"margin_top", 12)
	pad.add_theme_constant_override(&"margin_bottom", 12)
	box.add_child(pad)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 6)
	pad.add_child(vbox)

	_name_label = Label.new()
	_name_label.text = str(_data.get("name", ""))
	_name_label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.6))
	_name_label.add_theme_font_size_override(&"font_size", 16)
	vbox.add_child(_name_label)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.fit_content = true # report the full text height so the box can grow to fit it
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_text)

	# Options: right side, vertical, big touch targets, bottom-aligned.
	_options = VBoxContainer.new()
	_options.anchor_left = 1.0
	_options.anchor_right = 1.0
	_options.anchor_top = 1.0
	_options.anchor_bottom = 1.0
	_options.offset_left = -272
	_options.offset_right = -28
	_options.offset_top = -320
	_options.offset_bottom = -28
	_options.alignment = BoxContainer.ALIGNMENT_END
	_options.add_theme_constant_override(&"separation", 8)
	add_child(_options)


# --- Options mode -----------------------------------------------------------

func _show_options() -> void:
	_set_text(str(_data.get("greeting", "...")))
	_clear_options()
	for entry: Dictionary in _data.get("entries", []):
		_options.add_child(_option_button(entry))
	var bye: Button = Button.new()
	bye.text = "Good-bye"
	bye.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	bye.pressed.connect(hide)
	_options.add_child(bye)


func _option_button(entry: Dictionary) -> Button:
	var button: Button = Button.new()
	var icon: String = str(entry.get("icon", ""))
	var label: String = str(entry.get("label", "?"))
	button.text = ("%s  %s" % [icon, label]) if not icon.is_empty() else label
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.pressed.connect(_on_entry.bind(entry))
	return button


func _on_entry(entry: Dictionary) -> void:
	if entry.has("lines"):
		_lines = entry["lines"]
		_line_index = 0
		_show_line()
	elif entry.has("menu"):
		hide()
		ClientState.open_menu_requested.emit(entry["menu"], entry["arg"])


# --- Line-reading mode ------------------------------------------------------

func _show_line() -> void:
	if _line_index >= _lines.size():
		_show_options() # finished talking → back to the options
		return
	_set_text(str(_lines[_line_index]))
	_clear_options()
	var cont: Button = Button.new()
	cont.text = "Continue" if _line_index < _lines.size() - 1 else "Back"
	cont.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	cont.pressed.connect(_on_continue)
	_options.add_child(cont)


## First click finishes the typewriter; the next advances (classic Undertale).
func _on_continue() -> void:
	if _typing:
		_finish_typing()
		return
	_line_index += 1
	_show_line()


# --- Typewriter -------------------------------------------------------------

func _set_text(bbcode: String) -> void:
	_text.text = bbcode
	_fit_box.call_deferred() # grow the box to the new text once it's laid out at its width
	_text.visible_ratio = 0.0
	_typing = true
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	var chars: int = maxi(1, _text.get_total_character_count())
	_type_tween = create_tween()
	_type_tween.tween_property(_text, ^"visible_ratio", 1.0, chars / TYPE_CPS)
	# Just clear the flag on natural completion — don't kill the tween from inside
	# its own callback. The skip path (_finish_typing) does the killing.
	_type_tween.tween_callback(func() -> void: _typing = false)


func _finish_typing() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_text.visible_ratio = 1.0
	_typing = false


func _clear_options() -> void:
	for child: Node in _options.get_children():
		_options.remove_child(child)
		child.queue_free()


## Grow the text box upward to fit the current text. The bottom edge stays pinned (the box is
## already at the screen bottom); only the top moves up. Deferred from _set_text so the
## RichTextLabel has laid out at its wrapped width before we read its content height.
func _fit_box() -> void:
	if _box == null or _text == null:
		return
	var content_h: float = _text.get_content_height()
	# name label (~22) + vbox separation (6) + text + box padding (12 top + 12 bottom).
	var needed: float = 22.0 + 6.0 + content_h + 24.0
	_box.offset_top = _box.offset_bottom - maxf(needed, 104.0)
