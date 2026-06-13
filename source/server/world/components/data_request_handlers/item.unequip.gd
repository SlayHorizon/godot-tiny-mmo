extends DataRequestHandler
## Unequip whatever is in a given gear slot (e.g. &"weapon", &"torso").


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var slot: StringName = StringName(str(args.get("slot", "")))
	if slot.is_empty():
		return {"ok": false}

	# Only act if the slot currently holds an item.
	var item_id: int = int(player.equipment_component.slots.values.get(slot, 0))
	if item_id <= 0:
		return {"ok": false}

	# Same combat lock as equipping — armor/rings stay put mid-fight, but the
	# weapon slot is exempt (weapon swapping is core combat).
	if player.is_in_combat() and slot != &"weapon":
		return {"ok": false, "reason": "in_combat"}

	player.equipment_component.unequip(slot)
	# Move the item back into the inventory.
	Inventory.add_item(player.player_resource.inventory, item_id, 1)
	player.player_resource.equipment.erase(slot)
	return {"ok": true}
