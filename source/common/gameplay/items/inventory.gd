class_name Inventory
## Stateless helpers for the player inventory data model.
##
## Format (instance-based):
##     { slot_uid: int -> { "id": item_id: int, "a": amount: int } }
##
## Each slot is a distinct stack/instance. The "id" is the item registry id;
## per-instance data (durability, rolls, ...) can be added to the slot dict later
## without another migration. Stackable items merge into one slot; non-stackable
## items each get their own slot.
##
## Note: stored as JSON in SQLite, which turns int keys into strings and ints into
## floats on load. Always run loaded data through normalize() first.


## Convert raw JSON-loaded data into a clean { int: { "id": int, "a": int } } dict.
static func normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary
	for key in raw:
		var slot: Dictionary = raw[key]
		out[int(key)] = {
			"id": int(slot.get("id", 0)),
			"a": int(slot.get("a", 1)),
		}
	return out


## Add an item to the inventory, stacking when the item allows it.
static func add_item(inventory: Dictionary, item_id: int, amount: int = 1) -> void:
	if item_id <= 0 or amount <= 0:
		return

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	# Unknown items default to non-stackable (own slot) to stay safe.
	var stackable: bool = item != null and item.is_stackable()

	if stackable:
		for slot_uid in inventory:
			if int(inventory[slot_uid].get("id", 0)) == item_id:
				inventory[slot_uid]["a"] = int(inventory[slot_uid].get("a", 0)) + amount
				return
		# TODO: respect stack_limit by splitting into multiple slots when needed.

	inventory[next_uid(inventory)] = {"id": item_id, "a": amount}


## True if any slot holds the given item id.
static func has_item(inventory: Dictionary, item_id: int) -> bool:
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			return true
	return false


## Next free slot uid. INT64 headroom is effectively unlimited for inventory sizes.
static func next_uid(inventory: Dictionary) -> int:
	var max_uid: int
	for slot_uid in inventory:
		max_uid = max(max_uid, int(slot_uid))
	return max_uid + 1
