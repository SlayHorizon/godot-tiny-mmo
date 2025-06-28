class_name Guild
extends Resource


@export var guild_name: String
@export var leader_id: int
## player_id: rank_name
@export var members: Dictionary[int, String]


func add_member(player_id: int, rank: String) -> void:
	members[player_id] = rank


func remove_member(player_id: int) -> void:
	members.erase(player_id)
