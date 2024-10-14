class_name PlayerResource
extends Resource


@export var player_id: int

@export var display_name: String = "Player"
@export var character_class: String = "knight"

@export var golds: int = 0
@export var inventory: Dictionary = {}

@export var level: int = 0

var current_peer_id: int


func _init(_player_id: int) -> void:
	player_id = _player_id
