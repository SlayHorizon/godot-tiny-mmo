class_name BlockList
## Per-player block list, cached in memory so chat filtering is a O(1)
## dictionary lookup on the hot path. Authoritative storage is
## PlayerResource.blocked_ids (persisted as a JSON column on the players row,
## see world_store_sqlite.gd). This cache is hydrated when a player connects
## and cleared on disconnect — both wired in WorldServer.
##
## Asymmetric "ghost block": when X blocks Y, only X's view filters Y's
## chat. Y never knows. Standard social-MMO pattern to avoid retaliation
## cycles. Block applies to DM, world, guild, and overhead bubbles.

# blocker_player_id -> { blocked_player_id: true, ... }
static var _by_blocker: Dictionary[int, Dictionary]


## Returns true if [param blocker] has [param target] in their block list.
## Hot path — called on every chat broadcast per recipient.
static func is_blocked(blocker: int, target: int) -> bool:
	if blocker <= 0 or target <= 0:
		return false
	var bset: Dictionary = _by_blocker.get(blocker, {})
	return bset.has(target)


## Hydrate the cache from a player's persisted blocked_ids list. Called from
## WorldServer when a player connects.
static func set_for(blocker: int, ids: PackedInt64Array) -> void:
	if blocker <= 0:
		return
	var bset: Dictionary = {}
	for id: int in ids:
		bset[int(id)] = true
	_by_blocker[blocker] = bset


## Drop the cache for a disconnected player so we don't leak memory across
## sessions.
static func clear_player(blocker: int) -> void:
	_by_blocker.erase(blocker)


## In-memory add. The caller persists via WorldServer.database.save_player.
static func add(blocker: int, target: int) -> void:
	if blocker <= 0 or target <= 0:
		return
	if not _by_blocker.has(blocker):
		_by_blocker[blocker] = {}
	_by_blocker[blocker][target] = true


## In-memory remove. The caller persists via WorldServer.database.save_player.
static func remove(blocker: int, target: int) -> void:
	if not _by_blocker.has(blocker):
		return
	_by_blocker[blocker].erase(target)


## Returns the blocked ids for [param blocker] as an Array of ints.
static func get_blocked(blocker: int) -> Array:
	if not _by_blocker.has(blocker):
		return []
	return _by_blocker[blocker].keys()
