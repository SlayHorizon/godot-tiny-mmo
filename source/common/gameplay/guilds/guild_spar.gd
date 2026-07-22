class_name GuildSpar
## Guild spar rating — the source of Guild.spar_score (docs/guild.md). Guild
## matches are EMERGENT, not a separate mode: called by SparringService at the
## end of every 2-team match of MIN_TEAM_SIZE+ per side.
##
## TWO rated tiers (owner-locked 2026-07-19):
## - GUILD vs GUILD (both teams fully tagged to one distinct guild each): the
##   full formula — base + capped duration bonus, underdog multiplier up to 2x,
##   loser drops half the winner's gain (semi zero-sum).
## - GUILD vs MIXED (only one team is full-guild): reduced FLAT stakes — there
##   is no enemy rating to compare, so no underdog math; a win pays small, a
##   loss costs a small flat amount (a guild duo stomped by two hidden
##   server-top randoms shouldn't bleed rating).
##
## Anti-farm = WIN-STREAK falloff, never a cooldown (owner call — rematches/
## revenge must always be worth playing): consecutive wins against the same
## opponent pay 100% / 50% / 25% / then 0. The opponent key is the enemy GUILD
## (guild tier) or the enemy LINEUP (mixed tier), and the streak resets when
## that opponent beats you — revenge always pays full. Streaks only scale
## FUTURE gains; earned rating is never clawed back.

# --- Guild vs guild ---
const BASE_WIN: int = 100
## Extra points for a fought match, scaling to DURATION_CAP_S then capped.
const DURATION_BONUS_MAX: int = 50
const DURATION_CAP_S: int = 180
## Underdog multiplier reaches 2x when the winner trailed by this many points.
const UNDERDOG_GAP_CAP: int = 1000

# --- Guild vs mixed (flat stakes, no rating on the other side) ---
const MIXED_BASE_WIN: int = 40
const MIXED_DURATION_BONUS_MAX: int = 20
## Flat rating loss when a full-guild team loses to a mixed team (floored at 0).
const MIXED_LOSS: int = 25

## Sides smaller than this never rate (1v1 stays a personal duel).
const MIN_TEAM_SIZE: int = 2
## Payout per consecutive win against the same opponent; past the list = 0.
const STREAK_MULTIPLIERS: Array[float] = [1.0, 0.5, 0.25]

## "g<gid>><opponent key>" -> consecutive rated wins (in-memory, resets on F5 —
## fine at alpha scale). Opponent key: "g<gid>" or "m<sorted player ids>".
static var _win_streaks: Dictionary = {}


## Settle a finished spar. No-op unless one side was a full-guild team.
## Fighters must still be connected to resolve their guild tags (a vanished
## fighter voids that side's guild status).
static func on_match_ended(world_server: Node, rosters: Array, winner_index: int, duration_s: int) -> void:
	if world_server == null or winner_index < 0 or rosters.size() != 2:
		return
	for roster: Array in rosters:
		if roster.size() < MIN_TEAM_SIZE:
			return
	var winner_roster: Array = rosters[winner_index]
	var loser_roster: Array = rosters[1 - winner_index]
	var winner_gid: int = _team_guild_id(world_server, winner_roster)
	var loser_gid: int = _team_guild_id(world_server, loser_roster)

	if winner_gid > 0 and loser_gid > 0 and winner_gid != loser_gid:
		_settle_guild_vs_guild(world_server, winner_gid, loser_gid, duration_s)
	elif winner_gid > 0 and loser_gid <= 0:
		_settle_guild_beat_mixed(world_server, winner_gid, loser_roster, duration_s)
	elif loser_gid > 0 and winner_gid <= 0:
		_settle_mixed_beat_guild(world_server, loser_gid, winner_roster)
	# Both mixed, or a same-guild scrim: nothing to rate.


# --- Guild vs guild -----------------------------------------------------------

static func _settle_guild_vs_guild(world_server: Node, winner_gid: int, loser_gid: int, duration_s: int) -> void:
	var winner: Guild = world_server.database.get_guild(winner_gid)
	var loser: Guild = world_server.database.get_guild(loser_gid)
	if winner == null or loser == null:
		return

	var mult: float = _take_streak(winner_gid, "g%d" % loser_gid)
	_reset_streak(loser_gid, "g%d" % winner_gid)
	var gained: int = int(round(points_for_win(winner.spar_score, loser.spar_score, duration_s) * mult))
	@warning_ignore("integer_division")
	var lost: int = mini(gained / 2, loser.spar_score)
	winner.spar_score += gained
	loser.spar_score -= lost

	var store: Variant = world_server.database.store
	store.add_guild_log(winner_gid, "spar_won", "", loser.guild_name, {"points": gained})
	store.add_guild_log(loser_gid, "spar_lost", "", winner.guild_name, {"points": lost})
	if gained > 0:
		GuildTrophies.check_and_announce(world_server, winner)
	world_server.database.save_guild(winner)
	world_server.database.save_guild(loser)

	if gained > 0:
		_push_to_guild(world_server, winner_gid, "Your guild defeated %s in a spar! +%d Spar Rating." % [loser.guild_name, gained])
		_push_to_guild(world_server, loser_gid, "Your guild lost a spar against %s. -%d Spar Rating." % [winner.guild_name, lost])
	else:
		_push_to_guild(world_server, winner_gid, "Your guild defeated %s again. No rating for a long win streak, beat someone new!" % loser.guild_name)
		_push_to_guild(world_server, loser_gid, "Your guild lost a spar against %s. Win one back to reset their streak!" % winner.guild_name)


# --- Guild vs mixed -----------------------------------------------------------

static func _settle_guild_beat_mixed(world_server: Node, winner_gid: int, loser_roster: Array, duration_s: int) -> void:
	var winner: Guild = world_server.database.get_guild(winner_gid)
	if winner == null:
		return

	var mult: float = _take_streak(winner_gid, _lineup_key(world_server, loser_roster))
	var points: float = float(MIXED_BASE_WIN)
	points += float(MIXED_DURATION_BONUS_MAX) * clampf(float(duration_s) / float(DURATION_CAP_S), 0.0, 1.0)
	var gained: int = int(round(points * mult))
	winner.spar_score += gained

	world_server.database.store.add_guild_log(winner_gid, "spar_won", "", "a mixed team", {"points": gained})
	if gained > 0:
		GuildTrophies.check_and_announce(world_server, winner)
	world_server.database.save_guild(winner)

	if gained > 0:
		_push_to_guild(world_server, winner_gid, "Your guild won a spar against a mixed team. +%d Spar Rating." % gained)
	else:
		_push_to_guild(world_server, winner_gid, "Your guild beat that lineup again. No rating for a long win streak.")


static func _settle_mixed_beat_guild(world_server: Node, loser_gid: int, winner_roster: Array) -> void:
	var loser: Guild = world_server.database.get_guild(loser_gid)
	if loser == null:
		return

	# Their lineup beating us clears our farm streak against them.
	_reset_streak(loser_gid, _lineup_key(world_server, winner_roster))
	var lost: int = mini(MIXED_LOSS, loser.spar_score)
	loser.spar_score -= lost

	world_server.database.store.add_guild_log(loser_gid, "spar_lost", "", "a mixed team", {"points": lost})
	world_server.database.save_guild(loser)
	if lost > 0:
		_push_to_guild(world_server, loser_gid, "Your guild lost a spar against a mixed team. -%d Spar Rating." % lost)
	else:
		_push_to_guild(world_server, loser_gid, "Your guild lost a spar against a mixed team.")


# --- Shared -------------------------------------------------------------------

## Winner's rating gain vs a rated guild: (base + capped duration bonus) x
## underdog multiplier. Streak multiplier applies on top at the call site.
static func points_for_win(winner_rating: int, loser_rating: int, duration_s: int) -> int:
	var points: float = float(BASE_WIN)
	points += float(DURATION_BONUS_MAX) * clampf(float(duration_s) / float(DURATION_CAP_S), 0.0, 1.0)
	var gap: int = loser_rating - winner_rating
	if gap > 0:
		points *= 1.0 + clampf(float(gap) / float(UNDERDOG_GAP_CAP), 0.0, 1.0)
	return int(round(points))


## Current streak multiplier vs [param opponent_key], then bump the streak.
static func _take_streak(guild_id: int, opponent_key: String) -> float:
	var key: String = "g%d>%s" % [guild_id, opponent_key]
	var streak: int = int(_win_streaks.get(key, 0))
	_win_streaks[key] = streak + 1
	return STREAK_MULTIPLIERS[streak] if streak < STREAK_MULTIPLIERS.size() else 0.0


static func _reset_streak(guild_id: int, opponent_key: String) -> void:
	_win_streaks.erase("g%d>%s" % [guild_id, opponent_key])


## The single guild EVERY fighter on [param roster] is tagged to, or 0 when the
## side is mixed, has untagged fighters, or someone disconnected.
static func _team_guild_id(world_server: Node, roster: Array) -> int:
	var gid: int = 0
	for peer: int in roster:
		var player: PlayerResource = world_server.connected_players.get(peer)
		if player == null or player.active_guild_id <= 0:
			return 0
		if gid == 0:
			gid = player.active_guild_id
		elif player.active_guild_id != gid:
			return 0
	return gid


## Stable key for a mixed team's exact player set (streaks survive requeues).
static func _lineup_key(world_server: Node, roster: Array) -> String:
	var ids: Array[int] = []
	for peer: int in roster:
		var player: PlayerResource = world_server.connected_players.get(peer)
		ids.append(player.player_id if player != null else 0)
	ids.sort()
	var parts: PackedStringArray = []
	for id: int in ids:
		parts.append(str(id))
	return "m%s" % ",".join(parts)


static func _push_to_guild(world_server: Node, guild_id: int, msg: String) -> void:
	if world_server.chat_service == null:
		return
	for peer_id: int in world_server.connected_players:
		var player: PlayerResource = world_server.connected_players[peer_id]
		if player != null and player.active_guild_id == guild_id:
			world_server.chat_service.push_system_to_player(null, player.player_id, msg)
