extends CanvasLayer
## Lightweight transient toasts (client only). Call from anywhere:
##   Toaster.toast("Saved!")
##   Toaster.toast("Mining — Level 2!", 3.0)
## Toasts stack at the top-center of the screen and each fades out then frees itself.
## Purely cosmetic feedback — never gameplay-authoritative.

## How many toasts can be on screen at once (oldest is dropped past this).
const MAX_TOASTS: int = 5

var _container: VBoxContainer


func _ready() -> void:
	# Mirrors ClientState/Client: this is client-only UI.
	if not OS.has_feature("client"):
		queue_free()
		return

	layer = 128 # Above the HUD and menus.
	_container = VBoxContainer.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_container.offset_top = 32.0
	_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	_container.add_theme_constant_override(&"separation", 6)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)


func toast(text: String, duration: float = 2.0) -> void:
	if _container == null:
		return

	# Drop the oldest toast(s) if we're at the cap.
	while _container.get_child_count() >= MAX_TOASTS:
		var oldest: Node = _container.get_child(0)
		_container.remove_child(oldest)
		oldest.queue_free()

	var panel: PanelContainer = _make_toast(text)
	_container.add_child(panel)

	var tween: Tween = create_tween()
	tween.tween_property(panel, ^"modulate:a", 1.0, 0.15)
	tween.tween_interval(duration)
	tween.tween_property(panel, ^"modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)


func _make_toast(text: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.modulate.a = 0.0

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override(&"panel", style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_right", 12)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_theme_constant_override(&"margin_bottom", 6)
	panel.add_child(margin)

	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(label)

	return panel
