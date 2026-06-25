class_name MasteryService
## Weapon mastery rules: tree discovery, point math, spend/respec/loadout
## validation, and applying the results to a live player (special-slot
## mounting + passive stat modifiers). Static-only, like BasingService.
##
## XP accrual itself lives on PlayerResource.add_mastery_xp (mirrors job
## skills); the kill hook is in HostileNpc._reward_killer. Full design:
## docs/mastery.md.


const TREES_DIR: String = "res://source/common/gameplay/mastery/trees/"

## Mastery level required before nodes of a tier can be bought.
const TIER_UNLOCK_LEVEL: Dictionary[int, int] = {1: 1, 2: 3, 3: 6}

static var _trees: Dictionary[StringName, MasteryTreeResource]
static var _trees_loaded: bool = false


## Every discovered tree, keyed by category. UIs iterate this (not the
## player's masteries) so categories at zero practice still show up.
static func trees() -> Dictionary[StringName, MasteryTreeResource]:
	if not _trees_loaded:
		_load_trees()
	return _trees


static func tree_for(category: StringName) -> MasteryTreeResource:
	return trees().get(category, null)


## Points spent in a tree = sum of owned nodes' tiers. Ids of nodes that no
## longer exist (removed content) cost nothing — they just stop counting.
static func spent_cost(entry: Dictionary, tree: MasteryTreeResource) -> int:
	var total: int = 0
	var spent: Dictionary = entry.get("spent", {})
	for node_id: String in spent:
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node != null:
			total += node.tier
	return total


## 1 point per mastery level (level 1 included — the first tier-1 pick is
## meant to be near-immediate, see docs/mastery.md).
static func available_points(entry: Dictionary, tree: MasteryTreeResource) -> int:
	var level: int = mini(int(entry.get("level", 1)), PlayerResource.MASTERY_LEVEL_CAP)
	return level - spent_cost(entry, tree)


## Buys a tree node. The category entry is only CREATED by practice (first
## kill with the weapon — add_mastery_xp), never by the menu: the first point
## must be earned, even if earning it takes one kill. Keeps the "you get good
## at what you practice" fantasy honest from first contact.
static func spend(resource: PlayerResource, category: StringName, node_id: StringName) -> Dictionary:
	var tree: MasteryTreeResource = tree_for(category)
	if tree == null:
		return {"ok": false, "reason": "no_tree"}
	var node: MasteryNode = tree.get_node_by_id(node_id)
	if node == null:
		return {"ok": false, "reason": "unknown_node"}
	if not resource.masteries.has(category):
		return {"ok": false, "reason": "no_mastery"}
	var entry: Dictionary = resource.get_mastery(category)
	var spent: Dictionary = entry["spent"]
	if spent.has(String(node_id)):
		return {"ok": false, "reason": "owned"}
	if int(entry["level"]) < int(TIER_UNLOCK_LEVEL.get(node.tier, 1)):
		return {"ok": false, "reason": "tier_locked"}
	# Upgrade chains learn in order: you must own the tier this one replaces.
	if not node.upgrades.is_empty() and not spent.has(String(node.upgrades)):
		return {"ok": false, "reason": "needs_lower"}
	if available_points(entry, tree) < node.tier:
		return {"ok": false, "reason": "no_points"}
	spent[String(node_id)] = true
	return {"ok": true, "points": available_points(entry, tree)}


## Wipes a category's spent points AND its loadout pick. Free during alpha so
## testers experiment — pricing comes later if it matters.
static func reset(resource: PlayerResource, category: StringName) -> Dictionary:
	if not resource.masteries.has(category):
		return {"ok": false, "reason": "no_mastery"}
	(resource.masteries[category]["spent"] as Dictionary).clear()
	resource.ability_loadout.erase(String(category))
	return {"ok": true}


## The "abilities" registry ids to mount in the weapon's special slots, ONE
## ENTRY PER LOADOUT SLOT POSITION (0 = that slot is empty), so a pick keeps
## the input key the player placed it on. The capacity gate is a WEIGHT
## BUDGET spent in slot order: a pick that doesn't fit the remaining budget,
## isn't owned, or isn't an ability resolves to 0 (stored but inert until a
## weapon that can channel it).
static func effective_special_ids(resource: PlayerResource, weapon_item: WeaponItem) -> Array[int]:
	var out: Array[int] = []
	if resource == null or weapon_item == null or weapon_item.category.is_empty():
		return out
	var tree: MasteryTreeResource = tree_for(weapon_item.category)
	if tree == null:
		return out
	var picks: Array = resource.ability_loadout.get(String(weapon_item.category), [])
	var entry: Dictionary = resource.masteries.get(weapon_item.category, {})
	var spent: Dictionary = entry.get("spent", {})
	var budget: int = weapon_item.capacity
	var used_chains: Dictionary = {} # chain root id -> true (never mount a chain twice)
	for pick in picks:
		var resolved: int = 0
		var node_id: String = str(pick)
		if not node_id.is_empty() and spent.has(node_id):
			var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
			if node != null and node.ability != null:
				# Fire the EXACT tier the player slotted (no auto-bump to highest):
				# channeling a lighter tier to free weapon power for another ability
				# is a valid build. One tier per chain; over-budget picks stay inert.
				var root: String = String(_chain_root_id(tree, node))
				if node.tier <= budget and not used_chains.has(root):
					var ability_id: int = int(node.ability.get_meta(&"id", 0))
					if ability_id > 0:
						resolved = ability_id
						budget -= node.tier
						used_chains[root] = true
		out.append(resolved)
	return out


## The base (lowest) node of [param node]'s upgrade chain — follow `upgrades`
## down until a node with none. Standalone abilities return themselves.
static func _chain_root_id(tree: MasteryTreeResource, node: MasteryNode) -> StringName:
	var cur: MasteryNode = node
	while cur != null and not cur.upgrades.is_empty():
		var lower: MasteryNode = tree.get_node_by_id(cur.upgrades)
		if lower == null:
			break
		cur = lower
	return cur.id if cur != null else node.id


## The chain root id for a node — exposed for the loadout handler's dedupe and
## the panel's grouping.
static func chain_root_of(tree: MasteryTreeResource, node: MasteryNode) -> StringName:
	return _chain_root_id(tree, node)


## Re-derives everything mastery contributes to a live player: the synced
## special-slot ability id and the passive stat modifiers of the wielded
## category. Server-side only (stats are authoritative there); call after the
## spawn stat rebuild, on weapon swaps, and after spend/respec/loadout changes.
## Idempotent — previously applied passives are removed before re-applying.
static func refresh(player: Player) -> void:
	if player == null or not player.multiplayer.is_server():
		return
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return

	# Snapshot the resource caps so a passive that raises them can carry current
	# HP/MANA up by the same delta (a +max-health node should feel like a gain,
	# not leave you at 50/60). Skipped on the spawn pass, where HEALTH is still 0
	# and the spawn code refills to max right after.
	var old_hp_max: float = player.stats_component.get_stat(Stat.HEALTH_MAX)
	var old_mana_max: float = player.stats_component.get_stat(Stat.MANA_MAX)

	for applied: Dictionary in resource.applied_mastery_passives:
		player.stats_component.modify_stat(applied["stat"], -float(applied["value"]))
	resource.applied_mastery_passives.clear()

	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	player.equipment_component.set_special_abilities(effective_special_ids(resource, weapon_item))

	if weapon_item != null and not weapon_item.category.is_empty():
		var tree: MasteryTreeResource = tree_for(weapon_item.category)
		if tree != null and resource.masteries.has(weapon_item.category):
			var spent: Dictionary = (resource.masteries[weapon_item.category] as Dictionary).get("spent", {})
			for node: MasteryNode in tree.nodes:
				if node.ability != null or not spent.has(String(node.id)):
					continue
				for modifier: StatModifier in node.passive_modifiers:
					player.stats_component.modify_stat(modifier.stat_name, modifier.value)
					resource.applied_mastery_passives.append({"stat": modifier.stat_name, "value": modifier.value})

	_carry_current_to_max(player, Stat.HEALTH, Stat.HEALTH_MAX, old_hp_max)
	_carry_current_to_max(player, Stat.MANA, Stat.MANA_MAX, old_mana_max)


## When a max stat changed (a +/- max-health passive equipped/removed), shift
## the current value by the same delta and clamp — so gaining max HP heals you
## by that much and losing it trims you, instead of desyncing the bar. Skips the
## spawn pass (current still 0, refilled to max afterward).
static func _carry_current_to_max(player: Player, current: StringName, maxs: StringName, old_max: float) -> void:
	var new_max: float = player.stats_component.get_stat(maxs)
	var delta: float = new_max - old_max
	if is_zero_approx(delta):
		return
	var cur: float = player.stats_component.get_stat(current)
	if cur <= 0.0:
		return # dead / pre-spawn — leave it to the spawn refill
	player.stats_component.set_stat(current, clampf(cur + delta, 0.0, new_max))


static func _load_trees() -> void:
	_trees_loaded = true
	# Trees ship per-category (pilot: wand + sword) — the folder may not exist
	# yet, and list_directory on a missing dir spams errors, so probe first.
	if not DirAccess.dir_exists_absolute(TREES_DIR):
		return
	for file_name: String in ResourceLoader.list_directory(TREES_DIR):
		var tree: MasteryTreeResource = ResourceLoader.load(TREES_DIR + file_name) as MasteryTreeResource
		if tree != null and not tree.category.is_empty():
			_trees[tree.category] = tree
