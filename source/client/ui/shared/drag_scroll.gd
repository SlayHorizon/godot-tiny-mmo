class_name DragScroll
## Touch/mouse drag-to-scroll for a ScrollContainer. Godot's ScrollContainer already
## scrolls on a touch drag, but only if the drag actually reaches it: child Buttons default
## to MOUSE_FILTER_STOP and swallow it. [method enable] sets the tap-vs-drag deadzone and
## flips the content's STOP controls to PASS so a drag falls through to the scroll, while
## taps still fire and sliders / text fields keep their own drag.
##
## Call it once the scroll's content exists, and again after a dynamic list rebuilds its
## rows (it is idempotent). The shop wires the same behaviour inline as the original
## reference; everything else should go through this helper.
##
## Desktop note: a mouse drag only scrolls when the project's
## input_devices/pointing/emulate_touch_from_mouse is on. We keep that OFF on exports (it
## would flip desktop into touch mode and pop the twin-sticks), so on desktop this is
## touch-only; mobile gets it natively.


## Pixels of finger travel before a press becomes a scroll instead of a tap. One knob for
## the whole game: raise it if taps sometimes scroll, lower it if drags feel slow to grab.
const DEFAULT_DEADZONE: int = 5


## Make [param scroll]'s content drag-scrollable. Safe to call repeatedly.
static func enable(scroll: ScrollContainer, deadzone: int = DEFAULT_DEADZONE) -> void:
	if scroll == null:
		return
	scroll.scroll_deadzone = deadzone
	for child: Node in scroll.get_children():
		_pass_through(child)


## Recursively let drags fall through to the ScrollContainer. Only STOP controls are
## flipped (intentional IGNORE is left alone); Range (sliders/scrollbars) and text fields
## keep STOP so their own drags still work; nested ScrollContainers manage themselves.
static func _pass_through(node: Node) -> void:
	if node is ScrollContainer:
		return
	if node is Control:
		var control: Control = node as Control
		var keep_stop: bool = control is Range or control is LineEdit or control is TextEdit
		if not keep_stop and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
	for sub: Node in node.get_children():
		_pass_through(sub)
