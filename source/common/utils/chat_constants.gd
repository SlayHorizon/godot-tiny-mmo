class_name ChatConstants
extends RefCounted


# Keep stable across client + server.
const CHANNEL_WORLD: int = 0
const CHANNEL_TEAM: int = 1
const CHANNEL_GUILD: int = 2
const CHANNEL_SYSTEM: int = 3

const SYSTEM_SENDER_ID: int = 1
const SYSTEM_SENDER_NAME: String = "system"


static func channel_conversation_id(channel: int) -> String:
	return "global_%d" % channel


static func system_conversation_id(player_id: int) -> String:
	return "sys:%d" % player_id


static func dm_conversation_id(a: int, b: int) -> String:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	return "dm:%d:%d" % [lo, hi]


static func guild_conversation_id(guild_id: int) -> String:
	return "guild:%d" % guild_id


static func team_conversation_id(team_id: int) -> String:
	return "team:%d" % team_id
