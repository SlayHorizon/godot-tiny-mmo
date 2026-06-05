class_name GuildUpgrades
## Catalog + effect resolvers for Guild Hall upgrades. Pure/static — the only
## per-guild state is `Guild.upgrades` (upgrade_id -> level). Every perk here is
## HORIZONTAL (capacity / economy QoL / cosmetic), never combat power or faster
## progression — see the fair-perks principle in docs/guild.md.

# --- Upgrade ids ---
const MEMBER_CAPACITY: StringName = &"member_capacity"
const TREASURY_INCOME: StringName = &"treasury_income"
const DEFENDER_COUNT: StringName = &"defender_count"
const DEFENDER_TIER: StringName = &"defender_tier"

# --- Member capacity tuning ---
## Tag cap = how many members may be ONLINE and tagged into the guild at once.
const BASE_TAG_CAP: int = 15
const TAG_CAP_PER_LEVEL: int = 2
## Roster (total membership) cap = tag cap + this buffer, so some members can sit
## offline / tagged elsewhere without the leader kicking them to free space.
const ROSTER_BUFFER: int = 10

# --- Treasury income tuning ---
## Treasury (Guild Funds) granted per held flag per basing tick, before upgrades.
const BASE_TREASURY_INCOME: int = 10
const TREASURY_INCOME_PER_LEVEL: int = 5

## Cost to buy level L (1-indexed) = base_cost + (L - 1) * cost_step.
const CATALOG: Dictionary = {
	MEMBER_CAPACITY: {
		"name": "Member Capacity",
		"desc": "More members can tag in at once, and a bigger roster overall.",
		"max_level": 5,
		"base_cost": 50,
		"cost_step": 50,
	},
	TREASURY_INCOME: {
		"name": "Treasury Income",
		"desc": "Each held territory generates more Guild Funds per tick.",
		"max_level": 5,
		"base_cost": 75,
		"cost_step": 75,
	},
	# Defender upgrades are buyable & saved now; the spawn-on-capture logic ships
	# later (see docs/guild.md). Levels persist so they're ready when it lands.
	DEFENDER_COUNT: {
		"name": "Defenders",
		"desc": "NPC guards that spawn at your flag on capture. +1 per level. (effect coming soon)",
		"max_level": 5,
		"base_cost": 100,
		"cost_step": 100,
	},
	DEFENDER_TIER: {
		"name": "Defender Strength",
		"desc": "Makes your flag defenders tougher. (effect coming soon)",
		"max_level": 3,
		"base_cost": 150,
		"cost_step": 150,
	},
}


static func level_of(guild: Guild, upgrade_id: StringName) -> int:
	if guild == null:
		return 0
	return int(guild.upgrades.get(upgrade_id, 0))


static func max_level(upgrade_id: StringName) -> int:
	return int(CATALOG.get(upgrade_id, {}).get("max_level", 0))


static func is_maxed(guild: Guild, upgrade_id: StringName) -> bool:
	return level_of(guild, upgrade_id) >= max_level(upgrade_id)


## Cost to buy the NEXT level, or -1 if already maxed / unknown upgrade.
static func cost_for_next(guild: Guild, upgrade_id: StringName) -> int:
	var entry: Dictionary = CATALOG.get(upgrade_id, {})
	if entry.is_empty():
		return -1
	var level: int = level_of(guild, upgrade_id)
	if level >= int(entry.get("max_level", 0)):
		return -1
	return int(entry.get("base_cost", 0)) + level * int(entry.get("cost_step", 0))


# --- Effect resolvers ---

## Max members online & tagged into the guild at once.
static func tag_cap(guild: Guild) -> int:
	return BASE_TAG_CAP + level_of(guild, MEMBER_CAPACITY) * TAG_CAP_PER_LEVEL


## Max total roster (members dict size).
static func total_cap(guild: Guild) -> int:
	return tag_cap(guild) + ROSTER_BUFFER


## Treasury (Guild Funds) granted per held flag per basing tick.
static func treasury_per_flag(guild: Guild) -> int:
	return BASE_TREASURY_INCOME + level_of(guild, TREASURY_INCOME) * TREASURY_INCOME_PER_LEVEL


## Number of NPC defenders that spawn at a flag on capture (0 until upgraded).
static func defender_count(guild: Guild) -> int:
	return level_of(guild, DEFENDER_COUNT)


## Defender strength tier (1 = base, +1 per Defender Strength level).
static func defender_tier(guild: Guild) -> int:
	return 1 + level_of(guild, DEFENDER_TIER)


## ContentRegistry `enemy_types` slug of the archetype each Defender Strength
## tier uses. Matches the .tres filename basenames (the TinyMMO plugin slugs by
## basename). Guards reuse the generic hostile_npc scene + this archetype (no
## per-tier scenes); the flag resolves the slug to an id and ships it in the
## spawn init. Index = tier - 1.
const DEFENDER_ENEMY_SLUG_BY_TIER: Array[StringName] = [
	&"fungus", &"goblin", &"bandit", &"bandit_captain",
]


static func defender_enemy_slug(guild: Guild) -> StringName:
	var idx: int = clampi(defender_tier(guild) - 1, 0, DEFENDER_ENEMY_SLUG_BY_TIER.size() - 1)
	return DEFENDER_ENEMY_SLUG_BY_TIER[idx]
