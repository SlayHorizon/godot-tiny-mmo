extends Control
## HUD quick slots (keys 1 / 2 / 3): one-press access to anything usable from
## the bag — weapons and tools EQUIP (with swap), consumables USE — all
## through the same server-validated item.equip path, so a binding is pure
## convenience: pressing a slot for an item you no longer own is a no-op.
##
## Assignment happens in the inventory's detail strip (Hotkey button →
## SlotPickerOverlay). Bindings persist client-side per character.


const SLOT_COUNT: int = 3
const SLOT_ACTIONS: Array[StringName] = [
	&"player_quickslot_1", &"player_quickslot_2", &"player_quickslot_3",
]
const SETTINGS_SECTION: StringName = &"quick_slots"

var item_shortcuts: Array[Item]

@onready var slot_container: VBoxContainer = $VBoxContainer


func _ready() -> void:
	item_shortcuts.resize(SLOT_COUNT)
	for i: int in slot_container.get_child_count():
		var button: Button = slot_container.get_child(i) as Button
		button.pressed.connect(_trigger_slot.bind(i))
		# Corner key hint that survives the icon replacing the button text.
		var key_label: Label = Label.new()
		key_label.text = str(i + 1)
		key_label.add_theme_font_size_override(&"font_size", 9)
		key_label.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.85))
		key_label.position = Vector2(4, 2)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(key_label)

	ClientState.quick_slots.data_changed.connect(_on_slot_assigned)
	# Re-sync from any bindings already in memory (instance changes rebuild
	# the HUD; ClientState persists across them).
	for slot_index: Variant in ClientState.quick_slots.data:
		_on_slot_assigned(slot_index, ClientState.quick_slots.data[slot_index])
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer) -> void: _load_persisted())


## Keyboard 1/2/3. _unhandled_input on purpose: keys consumed by the GUI
## (typing numbers in chat) never reach here.
func _unhandled_input(event: InputEvent) -> void:
	for i: int in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			_trigger_slot(i)
			get_viewport().set_input_as_handled()
			return


func _trigger_slot(index: int) -> void:
	var item: Item = item_shortcuts[index] if index < item_shortcuts.size() else null
	if item == null:
		return
	# Toggle: tapping the slot of whatever you're HOLDING puts it away (1 = sword on,
	# 1 again = bare hands; a held potion toggles the same way). Otherwise equip it to
	# hand. Every hand item — weapon, potion, material — rides the &"weapon" slot.
	if _is_equipped(item):
		var slot_key: StringName = (item as GearItem).slot.key if item is GearItem else &"weapon"
		Client.request_data(
			&"item.unequip",
			_on_item_action_result,
			{"slot": slot_key},
			InstanceClient.current.name
		)
		return
	Client.request_data(
		&"item.equip",
		func(result: Dictionary) -> void:
			_on_item_action_result(result)
			_after_slot_used(result, index),
		{"id": int(item.get_meta(&"id", 0))},
		InstanceClient.current.name
	)


## Surfaces server rejections (combat lock, potion cooldown) as a toast so a
## key that "did nothing" explains itself.
func _on_item_action_result(result: Dictionary) -> void:
	match str(result.get("reason", "")):
		"in_combat":
			Toaster.toast("Can't change gear in combat (weapons only).")
		"cooldown":
			Toaster.toast("That's still on cooldown.")
		"level":
			Toaster.toast("Requires level %d to equip." % int(result.get("level", 0)))
		"cant_equip":
			Toaster.toast("You can't equip that.")


func _is_equipped(item: Item) -> bool:
	if ClientState.local_player == null:
		return false
	# Weapons/gear sit in their own slot; every other hand item (potions, materials)
	# rides the &"weapon" hand slot. Either way: are we holding THIS exact item now?
	var slot_key: StringName = (item as GearItem).slot.key if item is GearItem else &"weapon"
	var equipped_id: int = int(ClientState.local_player.equipment_component.slots.values.get(slot_key, 0))
	return equipped_id == int(item.get_meta(&"id", 0))


## Consumables: once the LAST one is used, drop the binding — a key that
## silently no-ops reads as a bug. While a stack remains, the binding stays.
## (Gear bindings persist forever; the item just bounces bag <-> body.)
func _after_slot_used(_response: Dictionary, index: int) -> void:
	var item: Item = item_shortcuts[index] if index < item_shortcuts.size() else null
	if item == null or not item is ConsumableItem:
		return
	var item_id: int = int(item.get_meta(&"id", 0))
	Client.request_data(
		&"inventory.get",
		func(inventory: Dictionary) -> void:
			if Inventory.count(inventory, item_id) <= 0:
				ClientState.quick_slots.set_key(index, null),
		{},
		InstanceClient.current.name
	)


## Reacts to ClientState.quick_slots writes (inventory Hotkey assignment or
## the persisted load below). null item = cleared slot.
func _on_slot_assigned(index: Variant, item: Variant) -> void:
	var i: int = int(index)
	if i < 0 or i >= SLOT_COUNT:
		return
	item_shortcuts[i] = item as Item
	var button: Button = slot_container.get_child(i) as Button
	if item != null:
		button.icon = (item as Item).item_icon
		button.text = "" if button.icon != null else String((item as Item).item_name)
	else:
		button.icon = null
		button.text = str(i + 1)
	_persist()


func _load_persisted() -> void:
	if ClientState.player_id <= 0:
		return
	var section: Dictionary = ClientState.settings.data.get(SETTINGS_SECTION, {})
	var saved: Dictionary = section.get(StringName(str(ClientState.player_id)), {})
	for slot_key: Variant in saved:
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(saved[slot_key])) as Item
		if item != null:
			ClientState.quick_slots.set_key(int(str(slot_key)), item)


func _persist() -> void:
	if ClientState.player_id <= 0:
		return
	var out: Dictionary = {}
	for i: int in SLOT_COUNT:
		if item_shortcuts[i] != null:
			out[str(i)] = int(item_shortcuts[i].get_meta(&"id", 0))
	if not ClientState.settings.data.has(SETTINGS_SECTION):
		ClientState.settings.data[SETTINGS_SECTION] = {}
	ClientState.settings.set_value(SETTINGS_SECTION, StringName(str(ClientState.player_id)), out)
