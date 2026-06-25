extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var item_id: int = int(args.get("id", 0))

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}
	# No item actions during the death/respawn window. Abilities are already gated
	# on is_dead (see recall.start.gd); consumables slipped through, letting players
	# heal and chug potions while dead. Server-authoritative, mirrors the ability gate.
	if player.is_dead:
		return {}
	var inventory: Dictionary = player.player_resource.inventory
	# Must own the item to act on it.
	if not Inventory.has_item(inventory, item_id):
		return {}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if not item:
		return {}

	# Gear that exists but can't be equipped: tell the player WHY instead of a
	# silent no-op (a too-high required_level is the usual culprit).
	if item is GearItem and not item.can_equip(player):
		if player.player_resource.level < item.required_level:
			return {"ok": false, "reason": "level", "level": item.required_level}
		return {"ok": false, "reason": "cant_equip"}

	if item is GearItem:
		# Combat lock — but WEAPONS stay swappable mid-fight (sword for melee,
		# bow for range is core play). Only armor/rings/etc. are locked so you
		# can't re-spec defenses under pressure.
		if player.is_in_combat() and item.slot.key != &"weapon":
			return {"ok": false, "reason": "in_combat"}
		var slot_key: StringName = item.slot.key
		# Weapons DRAW over a short cast (anti fast-swap + RPG commitment): the real
		# equip + inventory swap happen in begin_weapon_draw when the draw lands, and
		# abilities stay locked until then. Other gear equips instantly.
		if slot_key == &"weapon":
			player.begin_weapon_draw(item_id, slot_key)
			return {"ok": true}
		var previous_id: int = int(player.equipment_component.slots.values.get(slot_key, 0))
		if not player.equipment_component.equip_item(item_id):
			return {}
		# Move the item out of inventory; return any swapped-out gear to it.
		Inventory.remove_one_by_id(inventory, item_id)
		if previous_id > 0:
			Inventory.add_item(inventory, previous_id, 1)
		player.player_resource.equipment[slot_key] = item_id
	elif item is ConsumableItem and item.can_use(player):
		# Shared category cooldown (potion chugging) — server-authoritative.
		var category: StringName = item.cooldown_category
		var now: int = Time.get_ticks_msec()
		var cooldowns: Dictionary = player.player_resource.consumable_cooldowns
		if now < int(cooldowns.get(category, 0)):
			return {"ok": false, "reason": "cooldown"}
		item.on_use(player)
		if item.shared_cooldown_ms > 0:
			cooldowns[category] = now + item.shared_cooldown_ms
		# Root the drinker briefly so they can't run-and-chug.
		if item.use_freeze_ms > 0:
			WorldServer.curr.data_push.rpc_id(peer_id, &"player.freeze", {"ms": item.use_freeze_ms})
	return {}
