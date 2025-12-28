class_name PlayerResource
extends Resource


const ATTRIBUTE_POINTS_PER_LEVEL: int = 3
const HEALTH_MANA_SCALE_PER_LEVEL: float = 0.15  # 15% increase per level
const STAT_SCALE_PER_LEVEL: float = 0.05  # 5% increase per level for other stats

const BASE_STATS: Dictionary[StringName, float] = {
	Stat.HEALTH_MAX: 100.0,
	Stat.HEALTH: 100.0,
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

@export var golds: int
@export var inventory: Dictionary

@export var attributes: Dictionary[StringName, int]
@export var available_attributes_points: int

@export var level: int = 1
@export var experience: int = 0  # Current XP for current level
@export var total_experience: int = 0  # Cumulative XP from level 1

@export var guild: Guild
##
@export var server_roles: Dictionary

## Current Network ID
var current_peer_id: int

var stats: Dictionary


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


## Add experience and check for level-up
## Returns true if player leveled up
func add_experience(amount: int) -> bool:
	if amount <= 0:
		return false
	
	# Add to current experience
	experience += amount
	total_experience += amount
	
	# Check for level-up
	var leveled_up: bool = false
	while true:
		var xp_required: int = XPCalculator.get_xp_required_for_level(level + 1)
		if experience >= xp_required:
			# Level up!
			experience -= xp_required
			level_up()
			leveled_up = true
		else:
			break
	
	return leveled_up


func level_up() -> void:
	available_attributes_points += ATTRIBUTE_POINTS_PER_LEVEL
	level += 1


## Get scaled stats based on current level
## Returns a dictionary of stat_name -> scaled_value
func get_scaled_stats() -> Dictionary[StringName, float]:
	var scaled_stats: Dictionary[StringName, float] = {}
	
	# Health and mana scale at 15% per level
	var health_mana_multiplier: float = 1.0 + (level * HEALTH_MANA_SCALE_PER_LEVEL)
	# Other stats scale at 5% per level
	var other_stats_multiplier: float = 1.0 + (level * STAT_SCALE_PER_LEVEL)
	
	for stat_name: StringName in BASE_STATS:
		var base_value: float = BASE_STATS[stat_name]
		var scaled_value: float
		
		# Health and mana get higher scaling
		if stat_name == Stat.HEALTH_MAX or stat_name == Stat.HEALTH or \
		   stat_name == Stat.MANA_MAX or stat_name == Stat.MANA:
			scaled_value = base_value * health_mana_multiplier
		else:
			scaled_value = base_value * other_stats_multiplier
		
		scaled_stats[stat_name] = scaled_value
	
	return scaled_stats
