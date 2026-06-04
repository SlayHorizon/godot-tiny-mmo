class_name Guild
extends Resource


enum Permissions {
	NONE = 0,
	INVITE = 1 << 0,
	KICK = 1 << 1,
	PROMOTE = 1 << 2,
	EDIT = 1 << 3,
}


## Base roster cap fallback. The real cap is `GuildUpgrades.total_cap(guild)`,
## which scales with the Member Capacity upgrade; this equals the level-0 value
## (BASE_TAG_CAP + ROSTER_BUFFER = 15 + 10). Kept for old call sites / defaults.
const MAX_MEMBERS: int = 25

## Gold charged to create a guild.
const CREATION_COST: int = 150


## Rank ladder R5 (leader-tier, all perms) down to R1 (fresh member). `grade`
## drives the can-act hierarchy (lower grade = higher authority). New members
## join at the lowest rank ([constant DEFAULT_MEMBER_RANK]).
const DEFAULT_RANKS: Array[Dictionary] = [
	{
		"id": 0,
		"name": "R5",
		"permissions": 0x7FFFFFFF,
		"grade": 0,
	},
	{
		"id": 1,
		"name": "R4",
		"permissions": Permissions.INVITE | Permissions.KICK | Permissions.PROMOTE | Permissions.EDIT,
		"grade": 10,
	},
	{
		"id": 2,
		"name": "R3",
		"permissions": Permissions.INVITE | Permissions.KICK,
		"grade": 20,
	},
	{
		"id": 3,
		"name": "R2",
		"permissions": Permissions.INVITE,
		"grade": 30,
	},
	{
		"id": 4,
		"name": "R1",
		"permissions": Permissions.NONE,
		"grade": 100,
	},
]

## Rank id new members are added at (R1).
const DEFAULT_MEMBER_RANK: int = 4


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

## Player ids with a pending invite. Only a player on this list can accept and
## join (so invites can't be forged client-side). Cleared on accept.
@export var pending_invites: Array[int] = []

## Per-member permission overrides (player_id -> permission bitmask), OR'd onto
## the member's rank permissions. Lets an R5 grant a single player extra rights
## (e.g. recruit) without promoting them. See docs/guild.md.
@export var member_perms: Dictionary[int, int] = {}

# --- Basing / Glory ---
## Current-season Glory. Resets to 0 on each season rollover.
@export var seasonal_glory: int = 0
## Permanent Glory. Never reset.
@export var eternal_glory: int = 0
## Cumulative SG ever earned across all seasons — used only to compute EG so the
## 10:3 conversion is stateless and can't drift after season resets.
@export var total_sg_ever: int = 0
## Rolling count of kills-in-owned-territory contributed by guild members.
## Every KILLS_PER_GLORY hits grants +1 SG and the counter rolls over.
@export var kill_counter_for_glory: int = 0

# --- Lifetime stat counters (feed Profile stats + trophies; see docs/guild.md) ---
## Kills by tagged members in owned territory.
@export var total_kills: int = 0
## Cumulative seconds the guild has held at least one territory.
@export var territory_seconds: int = 0
## Guild-spar score (placeholder until guild spar exists).
@export var spar_score: int = 0

# --- Treasury (single abstract guild currency; see docs/guild.md) ---
## Guild funds. Earned from held territory and member gold deposits, spent on
## Guild Hall upgrades. Not transferable back to players.
@export var treasury: int = 0

# --- Guild Hall upgrades (upgrade_id -> level; see GuildUpgrades) ---
@export var upgrades: Dictionary[StringName, int] = {}


func add_member(player_id: int) -> void:
	members[player_id] = DEFAULT_MEMBER_RANK


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

	# Rank permissions OR the player's individual overrides.
	var combined: int = int(rank.get("permissions", Permissions.NONE)) | int(member_perms.get(player_id, 0))
	return (combined & permission) == permission


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
