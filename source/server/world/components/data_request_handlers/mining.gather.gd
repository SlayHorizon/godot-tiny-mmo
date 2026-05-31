extends DataRequestHandler


## Max distance (px) between the player and the node to allow gathering. Checked against
## the server's authoritative player position, never a client-sent one.
const GATHER_RANGE: float = 64.0


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var node_name: StringName = StringName(args.get("name", ""))
	if node_name == &"":
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	# Resolve the node from the player's map (authoritative; verifies it exists
	# here). Identity is the node's Godot-unique name within the Map root.
	var node: MineableNode = instance.instance_map.get_mineable(node_name)
	if node == null or node.ore == null:
		return {"ok": false}

	# Proximity: use the server-side player position, not anything client-sent.
	if player.global_position.distance_to(node.global_position) > GATHER_RANGE:
		return {"ok": false, "reason": "too_far"}

	# Tool: a matching tool must be equipped (in the weapon slot).
	if not _has_required_tool(player, node.required_tool):
		return {"ok": false, "reason": "no_tool"}

	# Read the current mining skill without creating it (only a successful gather should
	# bring a profession into existence).
	var mining_skill: Dictionary = player.player_resource.skills.get(MiningPerks.SKILL_NAME, {})
	var mining_level: int = int(mining_skill.get("level", 1))
	var mining_perks: Dictionary = mining_skill.get("perks", {})

	# Level gate for higher-tier veins.
	if mining_level < node.required_level:
		return {"ok": false, "reason": "level", "required_level": node.required_level}

	# Per-player cooldown on this specific node. Key is "<map>/<node_name>" so
	# cooldowns are scoped to map — gathering node "MineableNode2" in Map A
	# doesn't block the same-named node in Map B.
	var cooldown_key: StringName = StringName("%s/%s" % [instance.instance_map.scene_file_path, node_name])
	var now: int = Time.get_ticks_msec()
	var cooldowns: Dictionary = player.player_resource.gather_cooldowns
	if int(cooldowns.get(cooldown_key, 0)) > now:
		return {"ok": false, "reason": "cooldown"}

	# Shared node charges (lazy regen handled inside the node).
	if not node.try_consume_charge():
		return {"ok": false, "reason": "depleted"}

	# Bonus ore from baseline level + the Prospector perk.
	var amount: int = node.yield_amount
	if randf() < MiningPerks.effective_bonus_ore_chance(mining_level, mining_perks):
		amount += 1

	# Grant ore + mining xp (XP scaled by the Diligent perk).
	var ore_id: int = int(node.ore.get_meta(&"id", 0))
	Inventory.add_item(player.player_resource.inventory, ore_id, amount)
	var xp_gain: int = roundi(node.xp_reward * MiningPerks.xp_multiplier(mining_perks))
	var progress: Dictionary = player.player_resource.add_skill_xp(MiningPerks.SKILL_NAME, xp_gain)

	# Cooldown shortened by baseline level + the Efficient Mining perk.
	cooldowns[cooldown_key] = now + int(
		node.player_cooldown_seconds * 1000.0 * MiningPerks.effective_cooldown_factor(mining_level, mining_perks)
	)

	# How many perk points this gather's level-up(s) granted (for client feedback).
	var new_level: int = int(progress.get("level", 1))
	var perk_points_gained: int = MiningPerks.earned_points(new_level) - MiningPerks.earned_points(mining_level)

	return {
		"ok": true,
		"ore_id": ore_id,
		"amount": amount,
		"xp": xp_gain,
		"level": new_level,
		"leveled_up": progress.get("leveled_up", false),
		"perk_points_gained": perk_points_gained,
	}


func _has_required_tool(player: Player, tool_type: StringName) -> bool:
	# Empty required_tool = hand-gathering (herbs, flowers, etc.). Anyone can
	# pick those regardless of what's equipped — including bare-handed.
	if tool_type == &"":
		return true
	var equipped_id: int = int(player.equipment_component.slots.values.get(&"weapon", 0))
	if equipped_id <= 0:
		return false
	var item: Item = ContentRegistryHub.load_by_id(&"items", equipped_id)
	return item is ToolItem and item.tool_type == tool_type
