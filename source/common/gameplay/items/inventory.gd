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

	# `as Item` so a bad index entry (e.g. an id pointing at a PackedScene) yields
	# null instead of crashing the server on the strict assignment.
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	# Unknown items default to non-stackable (own slot) to stay safe.
	var stackable: bool = item != null and item.is_stackable()

	if stackable:
		for slot_uid in inventory:
			if int(inventory[slot_uid].get("id", 0)) == item_id:
				inventory[slot_uid]["a"] = int(inventory[slot_uid].get("a", 0)) + amount
				return
		# TODO: respect stack_limit by splitting into multiple slots when needed.

	inventory[next_uid(inventory)] = {"id": item_id, "a": amount}


## Remove up to `amount` from a slot, erasing the slot when it empties.
## Returns the amount actually removed (0 if the slot is missing).
static func remove_from_slot(inventory: Dictionary, slot_uid: int, amount: int = 1) -> int:
	if amount <= 0 or not inventory.has(slot_uid):
		return 0
	var have: int = int(inventory[slot_uid].get("a", 0))
	var removed: int = min(have, amount)
	var left: int = have - removed
	if left > 0:
		inventory[slot_uid]["a"] = left
	else:
		inventory.erase(slot_uid)
	return removed


## Remove one of the first slot holding the given item id. Returns true if removed.
static func remove_one_by_id(inventory: Dictionary, item_id: int) -> bool:
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			return remove_from_slot(inventory, slot_uid, 1) > 0
	return false


## Total amount of an item across all slots (used for currency / stack totals).
static func count(inventory: Dictionary, item_id: int) -> int:
	var total: int = 0
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			total += int(inventory[slot_uid].get("a", 0))
	return total


## Remove `amount` of an item across slots. No-op + false if not enough is held.
static func remove_amount_by_id(inventory: Dictionary, item_id: int, amount: int) -> bool:
	if amount <= 0 or count(inventory, item_id) < amount:
		return false
	var remaining: int = amount
	for slot_uid in inventory.keys():
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			remaining -= remove_from_slot(inventory, slot_uid, remaining)
			if remaining <= 0:
				break
	return true


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
