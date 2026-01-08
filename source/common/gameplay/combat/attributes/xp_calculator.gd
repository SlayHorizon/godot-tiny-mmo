class_name XPCalculator
extends RefCounted


## Tibia-inspired but gentler XP curve formula
## Formula: XP_required = BASE_XP * level * (level - 1) * CURVE_COEFFICIENT / DIVISOR

const BASE_XP: float = 50.0
const CURVE_COEFFICIENT: float = 1.5
const XP_FORMULA_DIVISOR: float = 3.0
const MIN_XP_PER_LEVEL: int = 50


## Calculate XP needed to reach a level from the previous level
## Returns the XP required for that specific level
static func get_xp_required_for_level(level: int) -> int:
	if level <= 1:
		return 0
	
	var xp_required: float = BASE_XP * level * (level - 1) * CURVE_COEFFICIENT / XP_FORMULA_DIVISOR
	var result: int = int(xp_required)
	
	# Ensure minimum XP per level
	if result < MIN_XP_PER_LEVEL:
		result = MIN_XP_PER_LEVEL
	
	return result


## Calculate cumulative XP needed to reach a level from level 1
## Returns total XP required to be at that level
static func get_total_xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	
	var total_xp: int = 0
	for lvl in range(2, level + 1):
		total_xp += get_xp_required_for_level(lvl)
	
	return total_xp


## Calculate what level a player should be based on their total XP
## Returns the level (minimum 1)
static func get_level_from_total_xp(total_xp: int) -> int:
	if total_xp <= 0:
		return 1
	
	var level: int = 1
	var accumulated_xp: int = 0
	
	# Iterate through levels until we exceed total_xp
	while true:
		var xp_for_next_level: int = get_xp_required_for_level(level + 1)
		if accumulated_xp + xp_for_next_level > total_xp:
			break
		accumulated_xp += xp_for_next_level
		level += 1
	
	return level

