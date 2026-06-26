class_name Item
extends Resource


# Definition
@export var item_name: StringName = &"ItemDefault"
@export var item_icon: Texture2D = preload("res://assets/sprites/items/icons/Icon271.png")
@export_multiline var description: String

## Can this item be drawn into the player's HAND (shown off, and tapped to act if it has
## an action)? True for nearly everything — set false only for items that should never be
## wielded. Gear ignores it (armor equips to its body slot via its own path); this gates
## plain items (materials, trophies) and consumables.
@export var holdable: bool = true

# Trading / Economy
## Marks this item as a currency (gold, event tokens, ...). Currency items are paid
## with / received in transactions, shown in the wallet, and hidden from the bag grid.
@export var is_currency: bool = false
## Can trade for goods between players.
@export var can_trade: bool = false
## Can sell to the consigment house.
@export var can_sell: bool = false
## Minimum price the item can be sold at consigment house.
## If 0 any price can be choosen.
## This is not shop price. If an item is sold at a shop, the price is defined in shop logic.
@export var market_minimum_price: int = 0
## Price an NPC vendor pays for this item when the player sells it.
## 0 = NPC vendors won't buy it (quest/bound/junk-safe default).
## Distinct from the consignment house fields above (player-to-player market).
@export var vendor_value: int


# Inventory
## If 0 no limit.
## 0 = pseudo infinite stack size
## 1 = non-stackable
@export_range(0, 99, 1.0) var stack_limit: int = 0
## Optional free-form tags for filters/crafting
@export var tags: PackedStringArray = []


func is_stackable() -> bool:
	return stack_limit == 0 or stack_limit > 1


## Human-readable stat lines for tooltips, auto-generated from the item's REAL data
## (never from the hand-written description), so changing a stat never needs a copy
## edit. Base items (materials, currency) have none. Subclasses override. Mirrors
## QuestObjective.describe().
## Each entry is {"text": String} plus a semantic tag the tooltip colours by:
## either "stat": <Stat key> (a modifier) or "kind": &"weapon"/"level"/"heal"/
## "mana"/"charges". The data layer stays presentation-free; colours live in the UI.
func stat_lines() -> Array[Dictionary]:
	return []


@warning_ignore("unused_parameter")
func can_use(player: Player) -> bool:
	return false


@warning_ignore("unused_parameter")
func on_use(character: Character) -> void:
	pass


## If NPC needs to handle an equipment, we don't use this check, we directly equip it.
@warning_ignore("unused_parameter")
func can_equip(player: Player) -> bool:
	return false


## Default for a PLAIN item (materials, trophies, ...): draw it into the hand to show
## off, with no action of its own. Gear / weapons / consumables override this with their
## own equip(). Gated on [member holdable] so a non-holdable item never mounts.
func equip(character: Character) -> void:
	if holdable:
		mount_in_hand(character)


func unequip(character: Character) -> void:
	unmount_hand(character)


# --- Generic in-hand mount (the unified hand) ---
## The bare in-hand rig: a sprite + the player's hand, with NO abilities of its own.
## ANY item that isn't a weapon mounts off this — consumables now, materials / trophies
## / a "circus ticket" later — so the hand logic lives in ONE place, not per item type.
## (A weapon overrides equip() with its own rig: right_hand_scene + skin + modifiers.)
## Loaded at RUNTIME, never preloaded: a parse-time preload on this BASE class forms an
## Item <-> weapon.tscn dependency cycle that nulls Item's implicit initializer, which
## makes EVERY item resource construct with default/null fields (a null description then
## crashes the tooltip). Runtime load() sidesteps the cycle; the scene caches after first.
const HAND_SCENE_PATH: String = "res://source/common/gameplay/items/weapons/weapon.tscn"


## Mount this item in [param character]'s hand off the generic rig: instance the hand
## scene, drive its sprite from this item's icon, and RETURN the node so the caller can
## install its action (a consumable adds a drink on the special slot; a plain material
## adds nothing and just shows). Runs on every machine off the synced hand slot, so
## everyone sees it. Returns null if the scene fails to load.
func mount_in_hand(character: Character) -> Weapon:
	var scene: PackedScene = load(HAND_SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var node: Weapon = scene.instantiate()
	node.character = character
	character.equipment_component.mounted_nodes[&"weapon"] = node
	character.right_hand_spot.add_child(node)
	node.show_held_icon(item_icon) # client-only inside; drives the in-hand sprite
	return node


## Generic hand unmount — free the node a matching mount_in_hand() created. Call from
## the item's unequip().
func unmount_hand(character: Character) -> void:
	var node: Node = character.equipment_component.mounted_nodes.get(&"weapon", null)
	if node:
		node.queue_free()
	character.equipment_component.mounted_nodes.erase(&"weapon")
