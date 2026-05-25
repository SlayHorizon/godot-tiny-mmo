class_name MiningPerks
## Mining profession perk math, shared by the gather handler (applies perks), the
## skill.perk.choose handler (validates picks) and skills.get (reports to the Jobs UI).
## Two layers, both tuned here:
##   - Baseline: automatic, grows every level (so each level feels like progress).
##   - Perks: chosen with perk points (1 per PERK_EVERY_LEVELS levels), stacking on top.

const SKILL_NAME: StringName = &"mining"

# --- Baseline (automatic per-level) ---
## Per-level cooldown reduction, floored at MIN_COOLDOWN_FACTOR of the node's base.
const COOLDOWN_REDUCTION_PER_LEVEL: float = 0.02
const MIN_COOLDOWN_FACTOR: float = 0.5
## Chance for +1 bonus ore, growing per level above 1, capped.
const BONUS_ORE_PER_LEVEL: float = 0.01
const MAX_BONUS_ORE_CHANCE: float = 0.25

# --- Perks (chosen) ---
## One perk point is earned every this many mining levels.
const PERK_EVERY_LEVELS: int = 3
## Absolute limits once baseline + chosen perks are combined.
const ABS_MIN_COOLDOWN_FACTOR: float = 0.3
const ABS_MAX_BONUS_ORE_CHANCE: float = 0.5
## Chooseable perks. `effect` selects which formula a rank feeds; `per_rank` is the
## bonus added per invested rank; effects stack ON TOP of the baseline.
const PERKS: Dictionary = {
	&"efficient": {"name": "Efficient Mining", "effect": "cooldown", "per_rank": 0.05, "max_rank": 3},
	&"prospector": {"name": "Prospector", "effect": "bonus_ore", "per_rank": 0.05, "max_rank": 3},
	&"diligent": {"name": "Diligent", "effect": "xp", "per_rank": 0.10, "max_rank": 3},
}


# --- Baseline helpers ---
static func cooldown_factor(level: int) -> float:
	return clampf(1.0 - COOLDOWN_REDUCTION_PER_LEVEL * float(level - 1), MIN_COOLDOWN_FACTOR, 1.0)


static func bonus_ore_chance(level: int) -> float:
	return minf(MAX_BONUS_ORE_CHANCE, BONUS_ORE_PER_LEVEL * float(level - 1))


# --- Perk-point bookkeeping ---
static func earned_points(level: int) -> int:
	return level / PERK_EVERY_LEVELS


static func spent_points(perks: Dictionary) -> int:
	var total: int = 0
	for perk_id in perks:
		total += int(perks[perk_id])
	return total


## Points available to spend, given a skill entry ({"level", "perks", ...}).
static func available_points(skill: Dictionary) -> int:
	return earned_points(int(skill.get("level", 1))) - spent_points(skill.get("perks", {}))


static func _rank(perks: Dictionary, perk_id: StringName) -> int:
	return int(perks.get(perk_id, 0))


# --- Effective values (baseline + chosen perks) ---
static func effective_cooldown_factor(level: int, perks: Dictionary) -> float:
	var factor: float = cooldown_factor(level) - PERKS[&"efficient"]["per_rank"] * _rank(perks, &"efficient")
	return clampf(factor, ABS_MIN_COOLDOWN_FACTOR, 1.0)


static func effective_bonus_ore_chance(level: int, perks: Dictionary) -> float:
	var chance: float = bonus_ore_chance(level) + PERKS[&"prospector"]["per_rank"] * _rank(perks, &"prospector")
	return minf(ABS_MAX_BONUS_ORE_CHANCE, chance)


static func xp_multiplier(perks: Dictionary) -> float:
	return 1.0 + PERKS[&"diligent"]["per_rank"] * _rank(perks, &"diligent")


## Human-readable effective-perk lines for the Jobs UI.
static func describe(level: int, perks: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"Gather speed +%d%%" % roundi((1.0 - effective_cooldown_factor(level, perks)) * 100.0),
		"Bonus ore +%d%%" % roundi(effective_bonus_ore_chance(level, perks) * 100.0),
		"Mining XP +%d%%" % roundi((xp_multiplier(perks) - 1.0) * 100.0),
	])
