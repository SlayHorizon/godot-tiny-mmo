class_name PlayerResource
extends Resource


@export var player_id: int
@export var account_name: String

@export var display_name: String = "Player"
@export var character_class: String = "knight"

@export var golds: int = 0
@export var inventory: Dictionary = {}

@export var level: int = 0

var current_peer_id: int


func _init(
	_player_id: int,
	_account_name: String,
	_display_name: String = display_name,
	_character_class: String = character_class
) -> void:
	player_id = _player_id
	account_name = _account_name
	display_name = _display_name
	character_class = _character_class
