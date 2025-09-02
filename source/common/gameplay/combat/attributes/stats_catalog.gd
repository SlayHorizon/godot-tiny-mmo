# StatsCatalog.gd
class_name StatsCatalog
extends Node

const HEALTH: StringName = &"health"
const HEALTH_MAX: StringName = &"health_max"

const MANA: StringName = &"mana"
const MANA_MAX: StringName = &"mana_max"

const ENERGY: StringName = &"energy"
const ENERGY_MAX: StringName = &"energy_max"

const SHIELD: StringName = &"shield"

const ARMOR: StringName = &"armor"           # physical resist
const MR: StringName = &"mr"                 # magic resist

const AD: StringName = &"ad"                 # attack damage
const AP: StringName = &"ap"                 # ability power (0 by default)

const ATTACK_SPEED: StringName = &"attack_speed"
const ATTACK_RANGE: StringName = &"attack_range"
const MOVE_SPEED: StringName = &"move_speed"

const CRIT_CHANCE: StringName = &"crit_chance"
const CRIT_DAMAGE: StringName = &"crit_damage"
const ABILITY_HASTE: StringName = &"ability_haste"
