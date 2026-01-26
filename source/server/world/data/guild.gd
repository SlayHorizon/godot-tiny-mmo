class_name Guild
extends Resource


enum Permissions {
	NONE = 0,
	INVITE = 1 << 0,
	KICK = 1 << 1,
	PROMOTE = 1 << 2,
	EDIT = 1 << 3,
}

const DEFAULT_RANKS: Dictionary[int, Dictionary] = {
	0: {
		"name": "Leader",
		"permissions": 0x7FFFFFFF,
		"grade": 0,
	},
	1: {
		"name": "Officer",
		"permissions": Permissions.INVITE | Permissions.KICK,
		"grade": 10,
	},
	2: {
		"name": "Member",
		"permissions": Permissions.NONE,
		"grade": 100,
	}
}

@export var guild_name: String
@export var leader_id: int

@export var motd: String
@export var description: String
@export var logo_id: int

## player_id: rank_name
@export var members: Dictionary[int, int]

@export var ranks: Dictionary[int, Dictionary] = DEFAULT_RANKS


func add_member(player_id: int) -> void:
	members[player_id] = 2


func remove_member(player_id: int) -> void:
	members.erase(player_id)


func get_member_rank(player_id: int) -> Dictionary:
	if not members.has(player_id):
		return {}
	return ranks.get(members[player_id], {})


func has_permission(player_id: int, permission: Permissions) -> bool:
	if player_id == leader_id:
		return true
	var rank: Dictionary = get_member_rank(player_id)
	if rank.is_empty():
		return false
	return (rank.get("permissions", Permissions.NONE) & permission) == permission


func can_act(actor_id: int, target_id: int) -> bool:
	if not members.has(actor_id) or not members.has(target_id):
		return false
	
	# Can't act on itself.
	if actor_id == target_id:
		return false
	
	# Leader can act on anyone (optional).
	if actor_id == leader_id:
		return true
	
	# Nobody can act on leader (optional but typical).
	if target_id == leader_id:
		return false

	return get_member_rank(actor_id).get("grade", 100) < get_member_rank(target_id).get("grade", 100)
