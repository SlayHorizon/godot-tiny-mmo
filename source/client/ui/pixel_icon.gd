class_name PixelIcon
extends RefCounted
## Crisp pixel-art icons in UI: NEAREST + INTEGER-scale-to-fit + WHOLE-pixel centering — the fix for the
## half-pixel smear that `Button.icon`/`expand_icon` and container centering produce at 1:1 (see the menu
## launcher + inventory icon saga). [method mount] adds one to a host; [method set_art] swaps its art.

## Adds a crisp icon as a child of [param host]: integer-scaled to fit the host, centered on whole GLOBAL
## pixels. Re-fits whenever the host's rect changes — DEFERRED, so it survives async / first-frame layout
## timing (an immediate fit caught freshly-built grids at 0-size, drawing tiny in the corner). Returns the
## TextureRect so callers that change the art later can pass it to [method set_art].
static func mount(host: Control, texture: Texture2D = null) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = texture
	host.add_child(icon)
	var fit: Callable = func() -> void: _fit(host, icon)
	icon.set_meta(&"_pixel_fit", fit)
	host.item_rect_changed.connect(func() -> void: fit.call_deferred())
	fit.call_deferred()
	return icon


## Swaps the art on an icon created by [method mount] and re-fits (a new art size can change the integer
## scale). Passing null hides it. Safe to call with a null icon.
static func set_art(icon: TextureRect, texture: Texture2D) -> void:
	if icon == null:
		return
	icon.texture = texture
	var fit: Variant = icon.get_meta(&"_pixel_fit", null)
	if fit is Callable:
		(fit as Callable).call_deferred()


static func _fit(host: Control, icon: TextureRect) -> void:
	if not is_instance_valid(host) or not is_instance_valid(icon) or not icon.is_inside_tree():
		return
	if icon.texture == null:
		icon.visible = false
		return
	icon.visible = true
	var art: Vector2 = icon.texture.get_size()
	if art.x <= 0.0 or art.y <= 0.0:
		return
	var box: float = minf(host.size.x, host.size.y)
	var factor: float = maxf(1.0, floorf(box / maxf(art.x, art.y)))
	icon.size = art * factor
	icon.global_position = (host.global_position + (host.size - icon.size) * 0.5).round()
