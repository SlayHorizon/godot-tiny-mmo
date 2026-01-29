class_name Guild
extends Resource


enum Permissions {
	NONE = 0,
	INVITE = 1 << 0,
	KICK = 1 << 1,
	PROMOTE = 1 << 2,
	EDIT = 1 << 3,
}


const DEFAULT_RANKS: Array[Dictionary] = [
	{
		"id": 0,
		"name": "Leader",
		"permissions": 0x7FFFFFFF,
		"grade": 0,
	},
	{
		"id": 1,
		"name": "Officer",
		"permissions": Permissions.INVITE | Permissions.KICK,
		"grade": 10,
	},
	{
		"id": 2,
		"name": "Member",
		"permissions": Permissions.NONE,
		"grade": 100,
	},
]


@export var guild_name: String
@export var guild_id: int
@export var leader_id: int

@export var motd: String
@export var description: String
@export var logo_id: int

## player_id -> rank_id
@export var members: Dictionary[int, int]

## Stored as an Array so JSON/SQLite round-trips cleanly.
## Each element: {"id": int, "name": String, "permissions": int, "grade": int}
@export var ranks: Array[Dictionary] = DEFAULT_RANKS


func add_member(player_id: int) -> void:
	members[player_id] = 2


func remove_member(player_id: int) -> void:
	members.erase(player_id)


func get_rank(rank_id: int) -> Dictionary:
	for rank: Dictionary in ranks:
		if int(rank.get("id", -1)) == rank_id:
			return rank

	return {}


func get_member_rank(player_id: int) -> Dictionary:
	if not members.has(player_id):
		return {}

	return get_rank(int(members[player_id]))


func has_permission(player_id: int, permission: Permissions) -> bool:
	if player_id == leader_id:
		return true

	var rank: Dictionary = get_member_rank(player_id)
	if rank.is_empty():
		return false

	return (int(rank.get("permissions", Permissions.NONE)) & permission) == permission


func can_act(actor_id: int, target_id: int) -> bool:
	if not members.has(actor_id) or not members.has(target_id):
		return false

	if actor_id == target_id:
		return false

	if actor_id == leader_id:
		return true

	if target_id == leader_id:
		return false

	var actor_grade: int = int(get_member_rank(actor_id).get("grade", 100))
	var target_grade: int = int(get_member_rank(target_id).get("grade", 100))

	return actor_grade < target_grade
