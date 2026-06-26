extends HBoxContainer
## MOBA-style ability bar: one tile per ability on the wielded weapon, in
## input order (LMB / Q / E). Each tile shows the ability's initials (art
## icons come later), its input key, its mana cost, a cooldown drain overlay
## with a seconds counter, and dims while mana is short. Pure display — every
## node is MOUSE_FILTER_IGNORE so the bar can never eat combat clicks.
##
## Rebuilds off EquipmentComponent.equipment_changed (weapon swaps AND
## mastery special-slot changes both emit it); cooldown/mana state polls in
## _process off the same AbilityResource instances the weapon fires with, so
## the bar can't drift from the truth.

const SLOT_KEYS: Array[String] = ["LMB", "Q", "E"]
const TILE_SIZE: Vector2 = Vector2(52, 52)
const MANA_SHORT_TINT: Color = Color(0.55, 0.62, 0.85)
const CHANNEL_GLOW: Color = Color(0.45, 1.0, 0.55)

var _weapon: Weapon
## Per-tile lookups: {"ability", "button", "sweep", "cd_label", "glow"}.
var _tiles: Array[Dictionary] = []
## Touch makes tiles tappable (fire-on-tap); mouse/gamepad keep them click-through.
var _touch_mode: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_mode = ClientState.input_type == InputComponent.InputType.TOUCH
	ClientState.input_changed.connect(_on_input_changed)
	ClientState.local_player_ready.connect(_on_local_player_ready)
	if ClientState.local_player != null:
		_on_local_player_ready(ClientState.local_player)


func _on_local_player_ready(local_player: LocalPlayer) -> void:
	var equipment: EquipmentComponent = local_player.equipment_component
	if not equipment.equipment_changed.is_connected(_on_equipment_changed):
		equipment.equipment_changed.connect(_on_equipment_changed)
	_rebuild.call_deferred()


func _on_equipment_changed(slot: StringName, _item_id: int) -> void:
	if slot == &"weapon" or slot == EquipmentComponent.SPECIAL_SLOT or slot == EquipmentComponent.SPECIAL_SLOT_2:
		# Mounting happens in the same call stack — rebuild once it settles.
		_rebuild.call_deferred()


## Touch state flips when the player switches input device (mirrors the twin-stick
## show/hide). Re-applies tap mode to live tiles so the bar becomes tappable the
## moment touch is detected, no rebuild needed.
func _on_input_changed(input_type: InputComponent.InputType) -> void:
	var touch: bool = input_type == InputComponent.InputType.TOUCH
	if touch == _touch_mode:
		return
	_touch_mode = touch
	for tile_info: Dictionary in _tiles:
		_apply_tap_mode(tile_info["button"] as Button)
		var key_label: Label = tile_info.get("key_label")
		if key_label != null:
			key_label.visible = not _touch_mode


## On touch, tiles accept taps (STOP) so a tap fires the ability; on mouse/gamepad
## they stay IGNORE so the bar never eats a combat click (you use the keys there).
## Firing goes straight through Weapon.press_slot, so it sidesteps the input
## component's _ui_blocks_combat gate.
func _apply_tap_mode(button: Button) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_STOP if _touch_mode else Control.MOUSE_FILTER_IGNORE


func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	_tiles.clear()
	_weapon = null
	if ClientState.local_player == null:
		return
	# The hand's mounted node IS the source of truth — a weapon shows its abilities, a
	# held consumable shows its one "drink" ability. No special case: equipment_changed
	# on the &"weapon" slot rebuilds us for every hand change (weapon swap, potion, bare).
	_weapon = ClientState.local_player.equipment_component.mounted_nodes.get(&"weapon", null) as Weapon
	if _weapon == null or not is_instance_valid(_weapon):
		return
	for i: int in _weapon.abilities.size():
		# A null PRIMARY (slot 0) = a held non-weapon item (potion) whose action sits on
		# the special slot. Don't render a dim empty "LMB" tile for it; null Q/E holes
		# (truthful mastery labels) still show.
		if i == 0 and _weapon.abilities[i] == null:
			continue
		_add_tile(i, _weapon.abilities[i])


func _add_tile(index: int, ability: AbilityResource) -> void:
	var tile: Button = Button.new()
	tile.theme_type_variation = &"SlotButton" # match the consumable hotbar look
	tile.custom_minimum_size = TILE_SIZE
	tile.focus_mode = Control.FOCUS_NONE
	_apply_tap_mode(tile)
	# Connections only fire while the tile is tappable (STOP, i.e. touch); on
	# IGNORE the button never receives input, so desktop is unaffected.
	tile.button_down.connect(_on_tile_down.bind(index))
	tile.button_up.connect(_on_tile_up.bind(index))
	if ability != null and ability.icon != null:
		tile.icon = ability.icon
		tile.add_theme_constant_override(&"icon_max_width", 44)
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif ability != null:
		tile.text = _initials(ability.name) # placeholder until the art pass
	if ability == null:
		tile.modulate.a = 0.35 # empty loadout slot (null hole) — key hint only
	add_child(tile)

	# Channel glow — first child so the key/mana labels render on top of it.
	var glow: ColorRect = ColorRect.new()
	glow.color = Color(CHANNEL_GLOW, 0.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	tile.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var key_label: Label = Label.new()
	key_label.text = SLOT_KEYS[index] if index < SLOT_KEYS.size() else str(index + 1)
	key_label.add_theme_font_size_override(&"font_size", 9)
	key_label.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.85))
	key_label.position = Vector2(4, 2)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.visible = not _touch_mode # on touch the tap IS the input; the key hint is just noise
	tile.add_child(key_label)

	# set_anchors_AND_OFFSETS everywhere below: the anchors-only variant keeps
	# the control's current (zero) rect — overlays collapse to the top-left.
	var sweep: ColorRect = ColorRect.new()
	sweep.color = Color(0.0, 0.0, 0.0, 0.55)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sweep.visible = false
	tile.add_child(sweep)

	var cd_label: Label = Label.new()
	cd_label.add_theme_font_size_override(&"font_size", 14)
	cd_label.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_label.visible = false
	tile.add_child(cd_label)
	cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if ability != null and ability.mana_cost > 0:
		var mana_label: Label = Label.new()
		mana_label.text = str(ability.mana_cost)
		mana_label.add_theme_font_size_override(&"font_size", 10)
		mana_label.add_theme_color_override(&"font_color", Color(0.45, 0.75, 1.0))
		mana_label.position = Vector2(TILE_SIZE.x - 16, TILE_SIZE.y - 15)
		mana_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(mana_label)

	_tiles.append({"ability": ability, "button": tile, "sweep": sweep, "cd_label": cd_label, "glow": glow, "key_label": key_label})


## Touch tap → fire the slot directly (press half). Empty loadout slots (null
## ability) and the no-weapon state are ignored.
func _on_tile_down(index: int) -> void:
	if _weapon == null or not is_instance_valid(_weapon) or ClientState.local_player == null:
		return
	# Bounds + null-hole check against the abilities array (the source of truth) — NOT
	# _tiles, which is packed by render order and desyncs from the ability index once a
	# null primary slot is skipped (a held consumable's [null, drink]).
	if index >= _weapon.abilities.size() or _weapon.abilities[index] == null:
		return
	_weapon.press_slot(index, ClientState.local_player)


## Touch release → release half (fires a charged two-phase ability; no-op for
## single-phase). Pairs with [method _on_tile_down] so a held tap charges.
func _on_tile_up(index: int) -> void:
	if _weapon == null or not is_instance_valid(_weapon) or ClientState.local_player == null:
		return
	if index >= _weapon.abilities.size() or _weapon.abilities[index] == null:
		return
	_weapon.release_slot(index, ClientState.local_player)


func _process(_delta: float) -> void:
	if _weapon == null or not is_instance_valid(_weapon) or ClientState.local_player == null:
		return
	var character: Character = ClientState.local_player
	var now: float = Time.get_ticks_msec() / 1000.0
	# What we're channeling (if anything) — read off the local player, which lives
	# inside the instance's multiplayer context (the HUD doesn't, so it can't ask).
	var channeling_name: String = ClientState.local_player.channeling_ability_name
	for tile_info: Dictionary in _tiles:
		var ability: AbilityResource = tile_info["ability"]
		if ability == null:
			continue
		var sweep: ColorRect = tile_info["sweep"]
		var cd_label: Label = tile_info["cd_label"]
		var button: Button = tile_info["button"]
		var glow: ColorRect = tile_info["glow"]
		# Channeling: light the tile and HIDE the cooldown until the channel ends.
		# The cooldown clock already started at press (mark_used), so when the
		# channel finishes the sweep just reveals the remaining time — exactly the
		# "active glow now, cooldown after" read.
		if not channeling_name.is_empty() and ability.name == channeling_name:
			sweep.visible = false
			cd_label.visible = false
			button.modulate = Color.WHITE
			glow.visible = true
			var pulse: float = 0.5 + 0.5 * sin(now * 6.0)
			glow.color = Color(CHANNEL_GLOW, 0.15 + 0.2 * pulse)
			continue
		glow.visible = false
		var cooldown: float = ability.effective_cooldown(character)
		var remaining: float = maxf(0.0, cooldown - (now - ability.last_action_time))
		if remaining > 0.05 and cooldown > 0.0:
			sweep.visible = true
			sweep.offset_top = -TILE_SIZE.y * clampf(remaining / cooldown, 0.0, 1.0)
			cd_label.text = "%.1f" % remaining
			cd_label.visible = true
		else:
			sweep.visible = false
			cd_label.visible = false
		# Mana-short tint: the press would be refused, say so before the click.
		if ability.mana_cost > 0 and character.stats_component.get_stat(Stat.MANA) < ability.mana_cost:
			button.modulate = MANA_SHORT_TINT
		else:
			button.modulate = Color.WHITE


## "Mending Bolt" -> "MB"; single-word names keep their first two letters.
func _initials(ability_name: String) -> String:
	var words: PackedStringArray = ability_name.split(" ", false)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return ability_name.left(2).capitalize()
