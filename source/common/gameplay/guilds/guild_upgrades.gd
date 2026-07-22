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
	DEFENDER_COUNT: {
		"name": "Defenders",
		"desc": "NPC guards that spawn around your flag when you capture it. One life each, no respawn until the next capture. +1 guard per level.",
		"max_level": 5,
		"base_cost": 100,
		"cost_step": 100,
	},
	DEFENDER_TIER: {
		"name": "Defender Strength",
		"desc": "Your flag defenders spawn as a tougher breed of guard.",
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
## DEDICATED guard archetypes (types/guards/, owner call 2026-07-19): guards
## get their own balance knobs and read as base security, not repurposed
## nature mobs from the PvE bands.
const DEFENDER_ENEMY_SLUG_BY_TIER: Array[StringName] = [
	&"guard_recruit", &"guard_veteran", &"guard_knight", &"guard_champion",
]

# --- Treasury sinks beyond upgrades ---
## Flat treasury price per non-default guild emblem (logo 0 is free).
## Catalog + valid id range live in GuildLogos.
const LOGO_COST: int = 250
## Treasury price per guard respawned via guild.defenders.reinforce.
const REINFORCE_COST_PER_GUARD: int = 25
## Treasury price PER CHANGE of the custom banner color (repeatable sink).
const BANNER_COLOR_COST: int = 100
## The purchasable banner colors — a CURATED preset list, not a free picker
## (owner call 2026-07-19): every entry is bright enough to read on the dark
## world, and the server only accepts colors from this list, so near-black /
## near-invisible banners can't happen. Hex, lowercase, leading #.
const BANNER_COLORS: PackedStringArray = [
	"#e2504c", "#f07f2e", "#f2c14b", "#8fd14f",
	"#4caf6e", "#39c6b5", "#4fa3e8", "#7d6ff0",
	"#c46ff0", "#f06fb2", "#e8e4da", "#8a93a8",
]


static func defender_enemy_slug(guild: Guild) -> StringName:
	var idx: int = clampi(defender_tier(guild) - 1, 0, DEFENDER_ENEMY_SLUG_BY_TIER.size() - 1)
	return DEFENDER_ENEMY_SLUG_BY_TIER[idx]


## Human-readable effect of [param upgrade_id] AT a given level — powers the
## "Now / Next" lines on Guild Hall upgrade rows so buyers see exactly what a
## level does before spending funds. Empty string for unknown ids.
static func effect_line_at(upgrade_id: StringName, level: int) -> String:
	match upgrade_id:
		MEMBER_CAPACITY:
			var tag: int = BASE_TAG_CAP + level * TAG_CAP_PER_LEVEL
			return "%d tagged online, %d roster" % [tag, tag + ROSTER_BUFFER]
		TREASURY_INCOME:
			return "%d funds per territory, per payout" % (BASE_TREASURY_INCOME + level * TREASURY_INCOME_PER_LEVEL)
		DEFENDER_COUNT:
			if level <= 0:
				return "no guards"
			return "%d guard%s per flag" % [level, "s" if level > 1 else ""]
		DEFENDER_TIER:
			var tier: int = 1 + level
			var idx: int = clampi(tier - 1, 0, DEFENDER_ENEMY_SLUG_BY_TIER.size() - 1)
			return "tier %d (%s)" % [tier, String(DEFENDER_ENEMY_SLUG_BY_TIER[idx]).capitalize()]
	return ""
