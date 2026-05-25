class_name PlayerResource
extends Resource


const ATTRIBUTE_POINTS_PER_LEVEL: int = 3

const BASE_STATS: Dictionary[StringName, float] = {
	Stat.HEALTH_MAX: 100.0,
	Stat.AD: 20.0,
	Stat.ARMOR: 15.0,
	Stat.MR: 15.0,
	Stat.MOVE_SPEED: 75.0,
	Stat.ATTACK_SPEED: 0.8
}

@export var player_id: int
@export var account_name: String

@export var display_name: String = "Player"
@export var skin_id: int = 1 # Default skin

@export var inventory: Dictionary
## Equipped gear: gear-slot key (&"weapon", &"torso", ...) -> item_id. Equipped items
## live here, NOT in inventory (they're moved out on equip, back on unequip).
@export var equipment: Dictionary

@export var attributes: Dictionary[StringName, int]
@export var available_attributes_points: int

@export var level: int

## Profession skills: skill_name (&"mining", &"woodcutting", ...) -> {"level": int, "xp": int}.
## Generalizes to any gathering/crafting profession; persisted as JSON.
@export var skills: Dictionary

## The guild currently selected as the player's active guild.
@export var active_guild_id: int
## All guilds the player is a member of.
## A player may belong to multiple guilds, but only one can be active at a time.
@export var joined_guild_ids: PackedInt64Array
## The guild in which the player holds the leader role.
@export var led_guild_id: int

@export var server_roles: Dictionary

@export var friends: PackedInt64Array

# Profile
@export var profile_status: String = "Hello I'am new!"
@export var profile_animation: String = "idle"

@export var last_position: Vector2 = Vector2.ZERO
@export var current_instance: String

## Current Network ID
var current_peer_id: int

var stats: Dictionary

## Per-node gather cooldowns (node_id -> next-ready time in ms). Runtime only, not persisted.
var gather_cooldowns: Dictionary


func init(
	_player_id: int,
	_account_name: String,
	_display_name: String = display_name,
	_skin_id: int = skin_id
) -> void:
	player_id = _player_id
	account_name = _account_name
	display_name = _display_name
	skin_id = _skin_id


func level_up() -> void:
	available_attributes_points += ATTRIBUTE_POINTS_PER_LEVEL
	level += 1


## Baseline xp needed to advance a profession skill (scales with current level).
const SKILL_XP_BASE: int = 100


## Returns the {"level", "xp", "perks"} entry for a skill, creating it at level 1 if
## missing. Also backfills "perks" on entries loaded from older saves.
func get_skill(skill_name: StringName) -> Dictionary:
	if not skills.has(skill_name):
		skills[skill_name] = {"level": 1, "xp": 0, "perks": {}}
	var skill: Dictionary = skills[skill_name]
	if not skill.has("perks"):
		skill["perks"] = {}
	return skill


func skill_xp_to_next(skill_level: int) -> int:
	return SKILL_XP_BASE * maxi(1, skill_level)


## Adds xp to a profession skill, applying any level-ups. Returns the new
## {"level", "xp", "leveled_up"} so callers can report progress to the client.
func add_skill_xp(skill_name: StringName, amount: int) -> Dictionary:
	var skill: Dictionary = get_skill(skill_name)
	skill["xp"] = int(skill["xp"]) + amount
	var leveled_up: bool = false
	while int(skill["xp"]) >= skill_xp_to_next(int(skill["level"])):
		skill["xp"] = int(skill["xp"]) - skill_xp_to_next(int(skill["level"]))
		skill["level"] = int(skill["level"]) + 1
		leveled_up = true
	return {"level": int(skill["level"]), "xp": int(skill["xp"]), "leveled_up": leveled_up}
