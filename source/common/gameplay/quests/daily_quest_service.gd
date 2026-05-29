class_name DailyQuestService
## Generates and tracks the player's daily quest board state. All methods are
## static; state lives on PlayerResource (daily_quests + dailies_refresh_at_ms).
##
## Flow:
##   - Player clicks the QuestBoard → quest.board.info handler.
##   - Service checks if dailies_refresh_at_ms <= now → if yes, reroll.
##   - Returns 3 daily descriptors with progress + claimable flag.
##   - Player kills a mob / picks up an item → on_kill / on_collect_changed
##     bump matching daily counters.
##   - Player clicks Claim on a complete daily → quest.board.claim → reward.

const POOL_PATH: String = "res://source/common/gameplay/quests/resources/daily_pool.tres"
const DAILY_COUNT: int = 3

static var _pool_cache: DailyQuestPool


# --- Public API ---

## Ensure the player has a current daily set. Rolls if stale or never rolled.
## Returns the resolved daily entries as a list of dicts (template + progress).
static func get_or_roll(player_res: PlayerResource) -> Array:
	_refresh_if_stale(player_res)
	return player_res.daily_quests


## Hook from HostileNpc._reward_killer. Bumps any KILL-kind dailies that match
## the enemy type just defeated.
static func on_kill(player_res: PlayerResource, enemy_type: StringName) -> void:
	if player_res == null:
		return
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return
	for entry: Variant in player_res.daily_quests:
		if entry is not Dictionary:
			continue
		var template: DailyQuestTemplate = pool.by_id(int((entry as Dictionary).get("template_id", 0)))
		if template == null or template.kind != DailyQuestTemplate.Kind.KILL:
			continue
		if template.enemy_type != enemy_type:
			continue
		var count: int = int((entry as Dictionary).get("count_so_far", 0))
		(entry as Dictionary)["count_so_far"] = mini(count + 1, template.required_amount)


## Claim a completed daily. Validates the entry is currently complete + not
## already claimed, grants the reward, marks claimed. Returns the result dict
## (or {ok:false, reason:...}).
static func claim(player_res: PlayerResource, template_id: int) -> Dictionary:
	_refresh_if_stale(player_res)
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return {"ok": false, "reason": "no_pool"}
	var template: DailyQuestTemplate = pool.by_id(template_id)
	if template == null:
		return {"ok": false, "reason": "no_template"}
	for entry: Variant in player_res.daily_quests:
		if entry is not Dictionary:
			continue
		if int((entry as Dictionary).get("template_id", 0)) != template_id:
			continue
		if bool((entry as Dictionary).get("claimed", false)):
			return {"ok": false, "reason": "already_claimed"}
		var progress: int = _progress(player_res, entry as Dictionary, template)
		if progress < template.required_amount:
			return {"ok": false, "reason": "incomplete"}
		(entry as Dictionary)["claimed"] = true
		return {
			"ok": true,
			"xp": template.reward_xp,
			"gold": template.reward_gold,
		}
	return {"ok": false, "reason": "not_in_set"}


## Compute progress for a daily entry. For KILL we read the stored counter; for
## COLLECT we count items in the bag in real time.
static func progress_for(player_res: PlayerResource, entry: Dictionary) -> int:
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return 0
	var template: DailyQuestTemplate = pool.by_id(int(entry.get("template_id", 0)))
	if template == null:
		return 0
	return _progress(player_res, entry, template)


# --- internals ---

static func _progress(player_res: PlayerResource, entry: Dictionary, template: DailyQuestTemplate) -> int:
	if template.kind == DailyQuestTemplate.Kind.COLLECT and template.item:
		var item_id: int = int(template.item.get_meta(&"id", 0))
		return mini(Inventory.count(player_res.inventory, item_id), template.required_amount)
	return mini(int(entry.get("count_so_far", 0)), template.required_amount)


## Roll 3 new dailies for the player and stamp the next refresh time.
static func _refresh_if_stale(player_res: PlayerResource) -> void:
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	if now_ms < player_res.dailies_refresh_at_ms and not player_res.daily_quests.is_empty():
		return
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		player_res.daily_quests = []
		return
	var eligible: Array[DailyQuestTemplate] = pool.eligible_for_level(player_res.level)
	eligible.shuffle()
	var picks: Array = []
	var taken: Dictionary = {}
	for t: DailyQuestTemplate in eligible:
		if picks.size() >= DAILY_COUNT:
			break
		if taken.has(t.template_id):
			continue
		taken[t.template_id] = true
		picks.append({
			"template_id": t.template_id,
			"count_so_far": 0,
			"claimed": false,
		})
	player_res.daily_quests = picks
	player_res.dailies_refresh_at_ms = _next_utc_midnight_ms(now_ms)


## Next 00:00 UTC after the given unix-ms.
static func _next_utc_midnight_ms(now_ms: int) -> int:
	const DAY_MS: int = 24 * 60 * 60 * 1000
	@warning_ignore("integer_division")
	var today_start: int = (now_ms / DAY_MS) * DAY_MS
	return today_start + DAY_MS


static func _load_pool() -> DailyQuestPool:
	if _pool_cache != null:
		return _pool_cache
	if not ResourceLoader.exists(POOL_PATH):
		return null
	_pool_cache = ResourceLoader.load(POOL_PATH) as DailyQuestPool
	return _pool_cache
