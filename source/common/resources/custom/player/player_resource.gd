class_name PlayerResource
extends Resource

@export var display_name: String = "Player"
@export var character_class: String = "knight"

@export var golds: int = 0
@export var inventory: Dictionary = {}

@export var level: int = 0

var current_peer_id: int
