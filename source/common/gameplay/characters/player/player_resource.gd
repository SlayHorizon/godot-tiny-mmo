class_name PlayerResource
extends Resource


const ATTRIBUTE_POINTS_PER_LEVEL: int = 3

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

@export var level: int

@export var guild: Guild
##
@export var server_roles: Dictionary

@export var last_position: Vector2 = Vector2.ZERO
@export var current_instance: String

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


func level_up() -> void:
	available_attributes_points += ATTRIBUTE_POINTS_PER_LEVEL
	level += 1
