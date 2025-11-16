class_name Stat


const HEALTH: StringName = &"health"
const HEALTH_MAX: StringName = &"health_max"

const MANA: StringName = &"mana"
const MANA_MAX: StringName = &"mana_max"

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

enum Id {
	HEALTH,
	HEALTH_MAX,

	MANA,
	MANA_MAX,

	ENERGY,
	ENERGY_MAX,

	SHIELD,

	ARMOR,# Physical resistance
	MR,# Magic resistance

	AD,# Attack Damage
	AP,# Ability Power

	ATTACK_SPEED,
	ATTACK_RANGE,

	MOVE_SPEED,

	CRIT_CHANCE,
	CRIT_DAMAGE,

	ABILITY_HASTE,
}
