class_name NPCResource
extends Resource


@export var display_name: String = "NPC"
@export var sprite_id: int = 1
@export var base_stats: Dictionary[StringName, float] = {}
@export var experience_reward: int = 0
@export var gold_reward: int = 0
@export var weapon_slug: String = ""
@export var attack_cooldown: float = 0.7
@export var detection_radius: float = 230.0
@export var loot_table: Array = []

