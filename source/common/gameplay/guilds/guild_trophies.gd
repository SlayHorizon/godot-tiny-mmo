class_name GuildTrophies
## Catalog + unlock logic for guild trophies — pure cosmetic prestige, zero
## gameplay power (fair-perks). Static code catalog on the GuildUpgrades
## pattern (owner call 2026-07-19; supersedes the old GuildTrophyResource
## idea): adding a trophy is one CATALOG entry + one generated icon.
##
## Unlocks evaluate wherever counters change (basing tick, kill flush, glory
## milestones, roster joins) and persist in Guild.trophies_unlocked so each
## announces exactly once. Guilds pick up to MAX_DISPLAYED for their profile.

## Max trophies a guild can pin to its profile.
const MAX_DISPLAYED: int = 3

# --- Stat keys (what a threshold measures) ---
const STAT_KILLS: StringName = &"kills"
const STAT_BASE_TIME: StringName = &"base_time"
const STAT_ETERNAL_GLORY: StringName = &"eternal_glory"
const STAT_SPAR: StringName = &"spar"
## Dynamic goal: roster size vs the guild's CURRENT total cap.
const STAT_ROSTER: StringName = &"roster"

## Ordered ladders. `threshold` 0 = dynamic goal (see progress()). Spar
## trophies wait for guild spar; treasury trophies skipped on purpose
## (current balance is gameable, no lifetime-deposit counter).
const CATALOG: Dictionary = {
	&"warband": {"name": "Warband", "desc": "100 kills by tagged members.", "stat": STAT_KILLS, "threshold": 100},
	&"warhost": {"name": "Warhost", "desc": "1,000 kills by tagged members.", "stat": STAT_KILLS, "threshold": 1000},
	&"legion": {"name": "Legion", "desc": "10,000 kills by tagged members.", "stat": STAT_KILLS, "threshold": 10000},
	&"foothold": {"name": "Foothold", "desc": "Held territory for 1 hour.", "stat": STAT_BASE_TIME, "threshold": 3600},
	&"stronghold": {"name": "Stronghold", "desc": "Held territory for 24 hours.", "stat": STAT_BASE_TIME, "threshold": 86400},
	&"dominion": {"name": "Dominion", "desc": "Held territory for 100 hours.", "stat": STAT_BASE_TIME, "threshold": 360000},
	&"honored": {"name": "Honored", "desc": "Earned 30 Eternal Glory.", "stat": STAT_ETERNAL_GLORY, "threshold": 30},
	&"renowned": {"name": "Renowned", "desc": "Earned 300 Eternal Glory.", "stat": STAT_ETERNAL_GLORY, "threshold": 300},
	&"eternal": {"name": "Eternal", "desc": "Earned 3,000 Eternal Glory.", "stat": STAT_ETERNAL_GLORY, "threshold": 3000},
	&"challenger": {"name": "Challenger", "desc": "Reached 500 Spar Rating.", "stat": STAT_SPAR, "threshold": 500},
	&"duelist": {"name": "Duelist", "desc": "Reached 2,500 Spar Rating.", "stat": STAT_SPAR, "threshold": 2500},
	&"gladiator": {"name": "Gladiator", "desc": "Reached 10,000 Spar Rating.", "stat": STAT_SPAR, "threshold": 10000},
	&"full_house": {"name": "Full House", "desc": "Filled every roster slot.", "stat": STAT_ROSTER, "threshold": 0},
}


static func display_name(trophy_id: StringName) -> String:
	return str(CATALOG.get(trophy_id, {}).get("name", String(trophy_id)))


## Generated placeholder icon (artist replaces the PNGs in place later).
static func icon_path(trophy_id: StringName) -> String:
	return "res://assets/sprites/guild_trophies/%s.png" % trophy_id


## Current / goal for a trophy — powers the trophy case's progress readouts.
## x = current, y = goal.
static func progress(guild: Guild, trophy_id: StringName) -> Vector2i:
	var entry: Dictionary = CATALOG.get(trophy_id, {})
	var goal: int = int(entry.get("threshold", 0))
	match entry.get("stat", &""):
		STAT_KILLS:
			return Vector2i(guild.total_kills, goal)
		STAT_BASE_TIME:
			return Vector2i(guild.territory_seconds, goal)
		STAT_ETERNAL_GLORY:
			return Vector2i(guild.eternal_glory, goal)
		STAT_SPAR:
			return Vector2i(guild.spar_score, goal)
		STAT_ROSTER:
			return Vector2i(guild.members.size(), GuildUpgrades.total_cap(guild))
	return Vector2i.ZERO


## Append any newly earned trophies to guild.trophies_unlocked and return the
## new ids. Caller is responsible for persisting the guild afterward.
static func evaluate(guild: Guild) -> Array[StringName]:
	var newly: Array[StringName] = []
	if guild == null:
		return newly
	for trophy_id: StringName in CATALOG:
		if guild.trophies_unlocked.has(trophy_id):
			continue
		var p: Vector2i = progress(guild, trophy_id)
		if p.y > 0 and p.x >= p.y:
			guild.trophies_unlocked.append(trophy_id)
			newly.append(trophy_id)
	return newly


## Evaluate + ceremony: each fresh unlock writes a guild-log entry and system-
## chats every tagged online member (glory-tick channel). Caller still saves
## the guild (unlocks ride the same save as the counter change that earned
## them). Server-side only.
static func check_and_announce(world_server: Node, guild: Guild) -> void:
	if world_server == null or guild == null:
		return
	for trophy_id: StringName in evaluate(guild):
		var trophy_name: String = display_name(trophy_id)
		world_server.database.store.add_guild_log(
			guild.guild_id, "trophy", "", "", {"trophy": trophy_name}
		)
		if world_server.chat_service == null:
			continue
		for peer_id: int in world_server.connected_players:
			var player: PlayerResource = world_server.connected_players[peer_id]
			if player != null and player.active_guild_id == guild.guild_id:
				world_server.chat_service.push_system_to_player(
					null, player.player_id,
					"Your guild earned the trophy '%s'!" % trophy_name
				)
