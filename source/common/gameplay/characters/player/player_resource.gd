class_name PlayerResource
extends Resource


const ATTRIBUTE_POINTS_PER_LEVEL: int = 3

## Profile customization limits, shared by the client edit UI and server validator.
const MAX_PROFILE_STATUS_LEN: int = 200
const ALLOWED_PROFILE_ANIMATIONS: PackedStringArray = ["idle", "run", "death"]
## Hard cap on how many achievement chips show on the profile trophy strip.
const MAX_DISPLAYED_TROPHIES: int = 3

const BASE_STATS: Dictionary[StringName, float] = {
	Stat.HEALTH_MAX: 50.0,
	# Low innate attack power on purpose: most of your damage comes from your
	# weapon's AD + the Strength attribute, so leveling and gear both matter and
	# a fresh level-1 is meant to feel weak. See AttributeMap / the weapon items.
	Stat.AD: 10.0,
	Stat.ARMOR: 15.0,
	Stat.MR: 15.0,
	# Mana gates SPECIAL abilities only (mana_cost on the AbilityResource);
	# basic attacks stay free. Regen lives in Player (server tick). Spirit
	# grows the pool.
	Stat.MANA_MAX: 50.0,
	Stat.MANA_REGEN: 0.5,
	Stat.MOVE_SPEED: 90.0,
	Stat.ATTACK_SPEED: 0.8
}

@export var player_id: int
@export var account_name: String

@export var display_name: String = "Player"
@export var skin_id: int = 1 # Default skin

@export var inventory: Dictionary
## Equipped gear: gear-slot key (&"weapon", &"torso", ...) -> item_id. Equipped items
## live here, NOT in inventory (they're moved out on equip, back on unequip).
@export var equipment: Dictionary

@export var attributes: Dictionary[StringName, int]
@export var available_attributes_points: int

@export var level: int = 1
## Character experience toward the next level (resets to the overflow on level-up).
@export var experience: int

## Profession skills: skill_name (&"mining", &"woodcutting", ...) -> {"level": int, "xp": int}.
## Generalizes to any gathering/crafting profession; persisted as JSON.
@export var skills: Dictionary

## Weapon mastery: category (&"wand", ...) -> {"level": int, "xp": int, "spent": Dictionary}.
## "spent" holds the bought mastery-tree node ids (node_id (String) -> true).
## Persisted as JSON (mastery_json column) together with ability_loadout.
@export var masteries: Dictionary

## Chosen special abilities per weapon category: category (String) -> Array of
## mastery node ids (String), in slot order. The server mounts the matching
## abilities into the weapon's special slots (Q, then E) when a weapon of that
## category is wielded, greedily within its weight capacity (MasteryService).
@export var ability_loadout: Dictionary

## Quests: quest_id (int) -> {"state": StringName, "progress": Dictionary(obj_index:int -> count:int)}.
## state is &"active" or &"turned_in". COLLECT objectives are derived from inventory live,
## so only KILL/CRAFT counts live in "progress". Persisted as JSON.
@export var quests: Dictionary

## The guild currently selected as the player's active guild.
@export var active_guild_id: int
## All guilds the player is a member of.
## A player may belong to multiple guilds, but only one can be active at a time.
@export var joined_guild_ids: PackedInt64Array
## The guild in which the player holds the leader role.
@export var led_guild_id: int

@export var server_roles: Dictionary

@export var friends: PackedInt64Array

## Per-player block list. When X has Y in here, the server suppresses every
## chat message Y produces (DM / world / guild / overhead bubbles) from
## reaching X's client. Asymmetric — Y never knows. Mirrors how friends is
## persisted (JSON column on the players row, see world_store_sqlite.gd).
@export var blocked_ids: PackedInt64Array

## Skins this character has purchased and may switch between (skin ids from the `sprites`
## registry). The currently EQUIPPED one is [member skin_id]; this is everything owned. The
## creation skin is seeded on character creation and backfilled on load, so the equipped
## skin is always in here. Persisted as owned_skins_json (mirrors [member friends]).
@export var owned_skins: PackedInt64Array

## Leaderboard counters with rolling day/week buckets. Keys:
## pvp_kills_day/week/total, pve_kills_day/week/total, lb_bucket_day_ms, lb_bucket_week_ms.
## Owned and rolled over by LeaderboardService.
@export var lb_stats: Dictionary

## Vanity titles ever earned by this character. Quest turn-ins can add to this
## list via QuestResource.grant_title. Player chooses which one is displayed via
## display_title.
@export var titles_unlocked: PackedStringArray
## Currently active title (shown on profile under display_name). Empty = no
## title displayed. Auto-set to a newly-granted title only if no title is
## currently active — so players don't lose their chosen banner.
@export var display_title: String
## Up to 3 trophies the player pins to their profile's right-side chip strip.
## Each entry must also be in titles_unlocked. Separate from display_title (the
## one shown under their name) — these are the "achievement flex" picks.
@export var displayed_trophies: PackedStringArray

## Daily quest board state: the 3 rolled quests for today and when they expire.
## Each entry is a Dictionary {template_id, count_so_far, claimed}.
## dailies_refresh_at_ms is the unix-ms of the next UTC midnight;
## DailyQuestService rerolls when now crosses it. Empty array = never rolled
## (first board click generates).
@export var daily_quests: Array
@export var dailies_refresh_at_ms: int

## Soft dungeon lockout: dungeon_name -> unix-SECONDS of the last completion
## reward. A clear within the dungeon's lockout window grants no reward (you can
## still run it to help a group). Persisted as dungeon_lockouts_json.
@export var dungeon_lockouts: Dictionary = {}

## Redeem codes this character has already claimed (upper-cased code strings).
## Per-character by design — see docs/redeem_codes.md. Persisted as
## redeemed_codes_json. Stops re-claiming the same code on this character.
@export var redeemed_codes: PackedStringArray

# Profile
@export var profile_status: String = "Hello I'am new!"
@export var profile_animation: String = "idle"

@export var last_position: Vector2 = Vector2.ZERO
@export var current_instance: String

## Current Network ID
var current_peer_id: int

## Server-side runtime stamp of when the current session began (Time.get_ticks_msec).
## Set on auth, consumed at disconnect to bump lb_stats["played_seconds"]. Not
## persisted — each session starts fresh.
var session_start_ms: int = 0

## True while the player is in a sparring match. Bypasses the zone PvP check
## in projectile/melee damage. Server-side runtime only — not persisted; if a
## player disconnects mid-match, SparringService ends the match cleanly so
## this never lingers across sessions.
var in_match: bool = false

var stats: Dictionary

## Live timed stat buffs ({stat, amount, expires_ms} — see BuffService). Runtime
## only on purpose: survives instance changes within a session, gone on logout.
var active_buffs: Array[Dictionary] = []

## Mastery passive modifiers currently applied to live stats ({stat, value}).
## Runtime only — rebuilt by MasteryService.refresh on spawn and weapon swaps.
var applied_mastery_passives: Array[Dictionary] = []

## Per-node gather cooldowns (node_id -> next-ready time in ms). Runtime only, not persisted.
var gather_cooldowns: Dictionary


func init(
	_player_id: int,
	_account_name: String,
	_display_name: String = display_name,
	_skin_id: int = skin_id
) -> void:
	player_id = _player_id
	account_name = _account_name
	display_name = _display_name
	skin_id = _skin_id


func level_up() -> void:
	available_attributes_points += ATTRIBUTE_POINTS_PER_LEVEL
	level += 1


## Character xp to advance a level: one clean linear-incremental curve — level N
## costs N × this. It's already super-linear, so each level is harder than the
## last (19→20 needs ~19× the first level) and the late game gets meaty on its
## own — no breakpoints or special-casing. Shape the PACING via xp SOURCES (quest
## rewards + mob xp), which is the honest, flexible lever. Total to cap (20) with
## base 70 ≈ 13,300.
const LEVEL_XP_BASE: int = 70


func level_xp_to_next() -> int:
	return LEVEL_XP_BASE * maxi(1, level)


## Adds character experience, applying any level-ups (each grants attribute points via
## level_up). Returns {"level", "experience", "levels_gained", "points_gained"} so the
## caller can report progress to the client.
# --- Quests ---

func quest_state(quest_id: int) -> StringName:
	return (quests.get(quest_id, {}) as Dictionary).get("state", &"")


func accept_quest(quest_id: int) -> void:
	if not quests.has(quest_id):
		quests[quest_id] = {"state": &"active", "progress": {}}


func quest_progress(quest_id: int, objective_index: int) -> int:
	var entry: Dictionary = quests.get(quest_id, {})
	return int((entry.get("progress", {}) as Dictionary).get(objective_index, 0))


## Increments a KILL/CRAFT objective's counter (only while the quest is active).
func advance_quest(quest_id: int, objective_index: int, amount: int = 1) -> void:
	var entry: Dictionary = quests.get(quest_id, {})
	if entry.get("state", &"") != &"active":
		return
	var progress: Dictionary = entry["progress"]
	progress[objective_index] = int(progress.get(objective_index, 0)) + amount


func set_quest_turned_in(quest_id: int) -> void:
	if quests.has(quest_id):
		quests[quest_id]["state"] = &"turned_in"


## Whether the "ready to turn in" nudge has been pushed for this quest, so a
## passive (COLLECT/inventory) completion toasts exactly once instead of on every
## tracker refresh. Persisted inside the quests blob; defaults false.
func quest_ready_notified(quest_id: int) -> bool:
	return bool((quests.get(quest_id, {}) as Dictionary).get("ready_notified", false))


func set_quest_ready_notified(quest_id: int, value: bool) -> void:
	if quests.has(quest_id):
		quests[quest_id]["ready_notified"] = value


func add_experience(amount: int) -> Dictionary:
	if amount <= 0:
		return {"level": level, "experience": experience, "levels_gained": 0, "points_gained": 0}
	experience += amount
	var levels_gained: int = 0
	while experience >= level_xp_to_next():
		experience -= level_xp_to_next()
		level_up()
		levels_gained += 1
	return {
		"level": level,
		"experience": experience,
		"levels_gained": levels_gained,
		"points_gained": levels_gained * ATTRIBUTE_POINTS_PER_LEVEL,
	}


## Baseline xp needed to advance a profession skill (scales with current level).
const SKILL_XP_BASE: int = 100


## Returns the {"level", "xp", "perks"} entry for a skill, creating it at level 1 if
## missing. Also backfills "perks" on entries loaded from older saves.
func get_skill(skill_name: StringName) -> Dictionary:
	if not skills.has(skill_name):
		skills[skill_name] = {"level": 1, "xp": 0, "perks": {}}
	var skill: Dictionary = skills[skill_name]
	if not skill.has("perks"):
		skill["perks"] = {}
	return skill


func skill_xp_to_next(skill_level: int) -> int:
	return SKILL_XP_BASE * maxi(1, skill_level)


## Adds xp to a profession skill, applying any level-ups. Returns the new
## {"level", "xp", "leveled_up"} so callers can report progress to the client.
func add_skill_xp(skill_name: StringName, amount: int) -> Dictionary:
	var skill: Dictionary = get_skill(skill_name)
	skill["xp"] = int(skill["xp"]) + amount
	var leveled_up: bool = false
	while int(skill["xp"]) >= skill_xp_to_next(int(skill["level"])):
		skill["xp"] = int(skill["xp"]) - skill_xp_to_next(int(skill["level"]))
		skill["level"] = int(skill["level"]) + 1
		leveled_up = true
	return {"level": int(skill["level"]), "xp": int(skill["xp"]), "leveled_up": leveled_up}


## Baseline xp to advance a weapon-mastery level (scales linearly, like skills).
const MASTERY_XP_BASE: int = 150
## 1 mastery point per level, so the cap is also the full point budget — tree
## content is sized so total node cost == cap (see docs/mastery.md).
const MASTERY_LEVEL_CAP: int = 10


## Returns the {"level", "xp", "spent"} entry for a weapon category, creating
## it at level 1 (= 1 spendable point) if missing.
func get_mastery(category: StringName) -> Dictionary:
	if not masteries.has(category):
		masteries[category] = {"level": 1, "xp": 0, "spent": {}}
	return masteries[category]


func mastery_xp_to_next(mastery_level: int) -> int:
	return MASTERY_XP_BASE * maxi(1, mastery_level)


## Adds weapon-mastery xp to a category, applying level-ups (frozen at the
## cap). Returns {"category", "level", "xp", "xp_to_next", "leveled_up",
## "started"} so the kill-reward push can report progress to the client —
## "started" marks the very first practice (entry creation at level 1), which
## deserves its own toast even though no level-UP happened.
func add_mastery_xp(category: StringName, amount: int) -> Dictionary:
	var started: bool = not masteries.has(category)
	var entry: Dictionary = get_mastery(category)
	var leveled_up: bool = false
	if amount > 0 and int(entry["level"]) < MASTERY_LEVEL_CAP:
		entry["xp"] = int(entry["xp"]) + amount
		while int(entry["xp"]) >= mastery_xp_to_next(int(entry["level"])):
			entry["xp"] = int(entry["xp"]) - mastery_xp_to_next(int(entry["level"]))
			entry["level"] = int(entry["level"]) + 1
			leveled_up = true
			if int(entry["level"]) >= MASTERY_LEVEL_CAP:
				entry["xp"] = 0
				break
	return {
		"category": String(category),
		"level": int(entry["level"]),
		"xp": int(entry["xp"]),
		"xp_to_next": mastery_xp_to_next(int(entry["level"])),
		"leveled_up": leveled_up,
		"started": started,
	}
