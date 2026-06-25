class_name Stat


const HEALTH: StringName = &"health"
const HEALTH_MAX: StringName = &"health_max"

const MANA: StringName = &"mana"
const MANA_MAX: StringName = &"mana_max"
## Mana restored per second by the instance status tick (base + Spirit + gear).
const MANA_REGEN: StringName = &"mana_regen"

const ENERGY: StringName = &"energy"
const ENERGY_MAX: StringName = &"energy_max"

const SHIELD: StringName = &"shield"

## Physical Resistance
const ARMOR: StringName = &"armor"
## Magic Resistance
const MR: StringName = &"mr"

## Attack Damage
const AD: StringName = &"ad"
## Ability Power
const AP: StringName = &"ap"

const ATTACK_SPEED: StringName = &"attack_speed"
const ATTACK_RANGE: StringName = &"attack_range"

const MOVE_SPEED: StringName = &"move_speed"

const CRIT_CHANCE: StringName = &"crit_chance"
const CRIT_DAMAGE: StringName = &"crit_damage"
const ABILITY_HASTE: StringName = &"ability_haste"


## Player-facing labels for stats shown in tooltips. Anything not listed falls back
## to a capitalized form of the raw key.
const DISPLAY_NAMES: Dictionary = {
	HEALTH_MAX: "Max Health",
	MANA_MAX: "Max Mana",
	MANA_REGEN: "Mana Regen",
	ARMOR: "Armor",
	MR: "Magic Resist",
	AD: "Attack Damage",
	AP: "Ability Power",
	ATTACK_SPEED: "Attack Speed",
	ATTACK_RANGE: "Attack Range",
	MOVE_SPEED: "Move Speed",
	CRIT_CHANCE: "Crit Chance",
	CRIT_DAMAGE: "Crit Damage",
	ABILITY_HASTE: "Ability Haste",
}


static func display_name(stat_name: StringName) -> String:
	return DISPLAY_NAMES.get(stat_name, String(stat_name).capitalize())
