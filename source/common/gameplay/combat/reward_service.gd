class_name RewardService
## Distributes a mob kill's rewards — XP, loot, weapon-mastery XP, quest + daily
## progress, basing glory, the PvE leaderboard, and level-milestone unlocks — to
## EVERY player who meaningfully damaged the mob, not just the last hitter. Lifted
## out of HostileNpc so the mob class stays "AI + combat": overworld mobs, dungeon
## bosses, and world bosses all reward through here. A mob with no xp_reward AND no
## loot (a dungeon "shadow") grants nothing, so it's skipped wholesale.
## Server-only.

## A player must have dealt at least this fraction of the mob's max HP to share in
## the kill (anti-leech). The killer is always included regardless.
const MIN_DAMAGE_FRACTION: float = 0.1


## [param contributors] = peer_id -> total damage dealt this life (HostileNpc
## tracks it). Server-only.
static func distribute(npc: HostileNpc, contributors: Dictionary, killer: Character) -> void:
	if not GameMode.is_world_server():
		return
	if npc.xp_reward <= 0 and (npc.loot == null or npc.loot.is_empty()):
		return # nothing to give (a shadow mob) — don't even resolve players
	var threshold: float = npc.stats_component.get_stat(Stat.HEALTH_MAX) * MIN_DAMAGE_FRACTION
	var killer_peer: int = -1
	if killer is Player and (killer as Player).player_resource != null:
		killer_peer = int((killer as Player).player_resource.current_peer_id)
	var rewarded: Dictionary[int, bool] = {}
	for peer_id: int in contributors:
		if peer_id != killer_peer and float(contributors[peer_id]) < threshold:
			continue
		var player: Player = _resolve_player(peer_id)
		if player != null:
			_reward(player, npc)
		rewarded[peer_id] = true
	if killer_peer > 0 and not rewarded.has(killer_peer):
		var kp: Player = _resolve_player(killer_peer)
		if kp != null:
			_reward(kp, npc)


## The live Player for a peer (null if they logged off / left), via its current
## instance — same lookup quest scoping uses.
static func _resolve_player(peer_id: int) -> Player:
	if WorldServer.curr == null:
		return null
	var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id)
	if inst == null:
		return null
	return inst.get_player(peer_id) as Player


## All of one participant's reward, and the combat.reward push to their client.
static func _reward(player: Player, npc: HostileNpc) -> void:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return

	var level_before: int = resource.level
	var progress: Dictionary = resource.add_experience(npc.xp_reward)
	var loot_gained: Array = _roll_loot(npc)
	for entry: Dictionary in loot_gained:
		Inventory.add_item(resource.inventory, int(entry["id"]), int(entry["amount"]))

	# Weapon mastery: practicing a category = killing with it. Same xp number.
	var mastery: Dictionary = {}
	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if weapon_item != null and not weapon_item.category.is_empty():
		mastery = resource.add_mastery_xp(weapon_item.category, npc.xp_reward)

	var peer_id: int = int(resource.current_peer_id)
	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"enemy_type": npc.enemy_type,
			"xp": npc.xp_reward,
			"level": int(progress.get("level", 1)),
			"levels_gained": int(progress.get("levels_gained", 0)),
			"points_gained": int(progress.get("points_gained", 0)),
			"experience": resource.experience,
			"xp_to_next": resource.level_xp_to_next(),
			"loot": loot_gained,
			"mastery": mastery,
		})

	var instance: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
	var quest_updates: Array = QuestService.on_kill(resource, npc.enemy_type, peer_id, instance)
	if peer_id > 0 and not quest_updates.is_empty():
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_updates})

	DailyQuestService.on_kill(resource, npc.enemy_type)
	LeaderboardService.record_pve_kill(player)

	if int(progress.get("levels_gained", 0)) > 0:
		var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
		LevelMilestoneService.on_levels_gained(resource, level_before, int(progress.get("level", 1)), inst)


## Rolls each loot entry; returns [{ "id", "amount", "name" }, ...].
static func _roll_loot(npc: HostileNpc) -> Array:
	var out: Array = []
	for drop: LootDrop in npc.loot:
		if drop == null or drop.item == null:
			continue
		if randf() <= drop.chance:
			var amount: int = randi_range(drop.min_amount, drop.max_amount)
			if amount > 0:
				out.append({
					"id": int(drop.item.get_meta(&"id", 0)),
					"amount": amount,
					"name": str(drop.item.item_name),
				})
	return out
