extends MenuShell
## Skin wardrobe — a big animated preview with prev/next arrows to browse every player skin,
## an idle/run/death animation toggle, and a single action button that Buys a locked skin
## (50g, which auto-equips it) or Equips an owned one. Equipping swaps the local player's
## sprite instantly (the server syncs :skin_id to everyone else). Opened from an NPC
## (WardrobeInteraction → open_menu_requested(&"wardrobe")); ownership refreshes on show.

const PREVIEW_BOX: float = 200.0
const PREVIEW_SCALE: float = 3.0
const SKIN_COST: int = 50
const ANIMS: Array[StringName] = [&"idle", &"run", &"death"]

var _skins: Array[int] = []
## skin_id -> true for skins the player owns (fetched from wardrobe.state on show).
var _owned: Dictionary[int, bool] = {}
var _idx: int = 0
var _anim: StringName = &"run"
var _gold: int = 0

var _preview: AnimatedSprite2D
var _name_label: Label
var _status_label: Label
var _action_button: Button
var _gold_label: Label
var _anim_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	build_shell("Wardrobe", null, true)
	_build_gold_display()
	_skins = PlayerSkins.ids()
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_on_shown())
	# The HUD instantiates this menu already-visible, then calls show() (a no-op while visible),
	# so visibility_changed does NOT fire on the very first open. Load once here so the gold
	# balance + the equipped-skin preview appear immediately instead of only after a reopen.
	_on_shown.call_deferred()


func _build_layout() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 10)
	content.add_child(col)

	# Big animated preview, centered (an AnimatedSprite2D hosted in a fixed-size Control,
	# like the gateway's character-creation preview).
	var preview_center: CenterContainer = CenterContainer.new()
	preview_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(preview_center)

	var preview_box: Control = Control.new()
	preview_box.custom_minimum_size = Vector2(PREVIEW_BOX, PREVIEW_BOX)
	preview_center.add_child(preview_box)

	_preview = AnimatedSprite2D.new()
	_preview.position = Vector2(PREVIEW_BOX * 0.5, PREVIEW_BOX * 0.5)
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # crisp pixels
	preview_box.add_child(_preview)

	# Prev / name / Next cycler.
	var nav: HBoxContainer = HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override(&"separation", 10)
	col.add_child(nav)

	var prev: Button = Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44, 44)
	prev.add_theme_font_size_override(&"font_size", 22)
	prev.pressed.connect(_cycle.bind(-1))
	nav.add_child(prev)

	_name_label = Label.new()
	_name_label.custom_minimum_size = Vector2(150, 44)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override(&"font_size", 18)
	nav.add_child(_name_label)

	var next: Button = Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44, 44)
	next.add_theme_font_size_override(&"font_size", 22)
	next.pressed.connect(_cycle.bind(1))
	nav.add_child(next)

	# Animation toggle (idle / run / death).
	var anim_row: HBoxContainer = HBoxContainer.new()
	anim_row.alignment = BoxContainer.ALIGNMENT_CENTER
	anim_row.add_theme_constant_override(&"separation", 6)
	col.add_child(anim_row)
	for anim: StringName in ANIMS:
		var btn: Button = Button.new()
		btn.text = String(anim).capitalize()
		btn.toggle_mode = true
		btn.button_pressed = (anim == _anim)
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_set_anim.bind(anim))
		anim_row.add_child(btn)
		_anim_buttons[anim] = btn

	# Status line + the buy/equip action.
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_status_label)

	_action_button = Button.new()
	_action_button.custom_minimum_size = Vector2(0, 44)
	_action_button.add_theme_font_size_override(&"font_size", 18)
	_action_button.pressed.connect(_on_action_pressed)
	col.add_child(_action_button)


# --- Gold ---

## Gold balance in the shell header (icon + amount), like the shop. Sourced from the server
## (wardrobe.state / wardrobe.buy) so the shown balance can't drift from what's actually charged.
func _build_gold_display() -> void:
	var gold_icon: TextureRect = TextureRect.new()
	gold_icon.custom_minimum_size = Vector2(20, 20)
	gold_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var gold: Item = ContentRegistryHub.load_by_id(&"items", Economy.gold_id())
	if gold != null:
		gold_icon.texture = gold.item_icon
	_gold_label = Label.new()
	_gold_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_right.add_child(gold_icon)
	header_right.add_child(_gold_label)
	# Sit the gold left of the Close button (build_shell added Close first).
	header_right.move_child(gold_icon, 0)
	header_right.move_child(_gold_label, 1)


func _set_gold(value: int) -> void:
	_gold = value
	if _gold_label != null:
		_gold_label.text = "%d" % value


# --- Data ---

func _on_shown() -> void:
	if _skins.is_empty():
		_status_label.text = "No skins available."
		return
	if InstanceClient.current == null:
		return
	Client.request_data(&"wardrobe.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_owned.clear()
	for id_v: Variant in data.get("owned", []):
		_owned[int(id_v)] = true
	_set_gold(int(data.get("gold", 0)))
	# Open on the skin you're currently wearing.
	var equipped_idx: int = _skins.find(_equipped_id())
	_idx = equipped_idx if equipped_idx >= 0 else 0
	_update_preview()


# --- Browsing ---

func _cycle(delta: int) -> void:
	if _skins.is_empty():
		return
	_idx = wrapi(_idx + delta, 0, _skins.size())
	_update_preview()


func _set_anim(anim: StringName) -> void:
	_anim = anim
	for key: StringName in _anim_buttons:
		_anim_buttons[key].button_pressed = (key == anim)
	_play_best_anim()


func _update_preview() -> void:
	if _idx < 0 or _idx >= _skins.size():
		return
	var skin_id: int = _skins[_idx]
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", skin_id) as SpriteFrames
	if _preview != null and frames != null:
		_preview.sprite_frames = frames
		_play_best_anim()
	_name_label.text = PlayerSkins.display_name(skin_id)
	_update_action()


## Play the selected animation, falling back to idle (then the first available clip) for
## skins that don't define it — so the preview never sits on a blank frame.
func _play_best_anim() -> void:
	if _preview == null or _preview.sprite_frames == null:
		return
	var frames: SpriteFrames = _preview.sprite_frames
	var anim: StringName = _anim
	if not frames.has_animation(anim):
		if frames.has_animation(&"idle"):
			anim = &"idle"
		else:
			var names: PackedStringArray = frames.get_animation_names()
			if names.is_empty():
				return
			anim = StringName(names[0])
	_preview.play(anim)


# --- Buy / equip ---

func _update_action() -> void:
	if _idx < 0 or _idx >= _skins.size():
		return
	var skin_id: int = _skins[_idx]
	if skin_id == _equipped_id():
		_action_button.text = "Equipped"
		_action_button.disabled = true
		_status_label.text = "This is your current look."
	elif _owned.get(skin_id, false):
		_action_button.text = "Equip"
		_action_button.disabled = false
		_status_label.text = "Owned."
	else:
		_action_button.text = "Buy — %d gold" % SKIN_COST
		var can_afford: bool = _gold >= SKIN_COST
		_action_button.disabled = not can_afford
		_status_label.text = "Locked." if can_afford else "Not enough gold (%d needed)." % SKIN_COST


func _on_action_pressed() -> void:
	if InstanceClient.current == null or _idx < 0 or _idx >= _skins.size():
		return
	var skin_id: int = _skins[_idx]
	if skin_id == _equipped_id():
		return
	_action_button.disabled = true
	if _owned.get(skin_id, false):
		Client.request_data(&"wardrobe.equip", _on_equipped.bind(skin_id), {"skin_id": skin_id}, String(InstanceClient.current.name))
	else:
		Client.request_data(&"wardrobe.buy", _on_bought.bind(skin_id), {"skin_id": skin_id}, String(InstanceClient.current.name))


func _on_bought(data: Dictionary, skin_id: int) -> void:
	if not data.get("ok", false):
		_status_label.text = _buy_error(str(data.get("reason", "")))
		_update_action()
		return
	_owned[skin_id] = true
	_set_gold(int(data.get("gold", _gold)))
	# Buying auto-equips the skin you were previewing.
	Client.request_data(&"wardrobe.equip", _on_equipped.bind(skin_id), {"skin_id": skin_id}, String(InstanceClient.current.name))


func _on_equipped(data: Dictionary, skin_id: int) -> void:
	if data.get("ok", false) and ClientState.local_player != null and is_instance_valid(ClientState.local_player):
		# Instant local swap (Character._set_skin_id); the server syncs :skin_id to others.
		ClientState.local_player.skin_id = skin_id
	_update_action()


func _equipped_id() -> int:
	if ClientState.local_player != null and is_instance_valid(ClientState.local_player):
		return ClientState.local_player.skin_id
	return 0


func _buy_error(reason: String) -> String:
	match reason:
		"no_gold":
			return "Not enough gold (%d needed)." % SKIN_COST
		"owned":
			return "You already own this."
		"invalid":
			return "That skin isn't available."
		_:
			return "Couldn't buy that skin."
