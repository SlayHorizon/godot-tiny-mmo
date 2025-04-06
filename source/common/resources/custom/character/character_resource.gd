class_name CharacterResource
extends Resource


@export var character_name: String

@export var character_sprite: SpriteFrames

# Stats at level 1
@export var base_health: int = 30
@export var base_mana: int = 10
@export var base_attack_damage: int = 5
@export var base_magic_power: int = 4
@export var base_attack_speed: float = 0.7
@export var base_move_speed: float = 300

# Stats progression per level
# (For linear progression, can be changed to some kind of formula)
@export var health_per_level: float = 10
@export var mana_per_level: float = 3
@export var attack_damage_per_level: float = 2
@export var magic_power_per_level: float = 1.5
@export var attack_speed_per_level: float = 0.015

@export var passive_abilities: Array[AbilityResource]
@export var active_abilities: Array[AbilityResource]

@export var description: String = ""

# Possible character class evolution
# Example: knight -> [holy knight or dark knight]
@export var evolution: Array[CharacterResource]
