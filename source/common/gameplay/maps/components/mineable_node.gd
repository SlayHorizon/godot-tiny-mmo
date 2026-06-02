class_name MineableNode
extends Area2D
## A world-space gathering node (ore vein, herb patch, etc.). v2: swing-based.
## A pickaxe swing's hitbox overlaps this Area2D → register_pickaxe_hit fires
## server-side, accumulates per-player extraction progress, and triggers a
## yield once the player's progress drains the per-extraction HP.
##
## Design notes:
## - **Shared charges**: the node's pool of yields is shared (3 by default).
## - **Per-player progress**: each player tracks their own swings toward the
##   next yield, so two players mining the same vein don't steal from each
##   other's progress.
## - **Continuous regen while charges > 0**: +1 every charge_regen_seconds.
## - **Snap-refill when fully depleted**: a depleted node waits longer
##   (depleted_recharge_seconds), then refills all charges at once. Prevents
##   the "1 charge appears → 3 players race to grab it" griefing pattern.
## - **Job XP routing**: job_xp is a dict so a healing herb can grant both
##   harvesting AND medicine; an ore vein just grants mining.
##
## Setup: instance mineable_node.tscn under the Map, assign ore + job_xp,
## position it. Identity is the node's Godot-unique name within the Map.

## The item granted per yield. Use a MaterialItem with vendor_value set.
@export var ore: Item
@export var yield_amount: int = 1
## How many job-XP grants happen on each yield. Examples:
##   { &"mining": 10 }                          # ore vein
##   { &"harvesting": 5, &"medicine": 5 }       # herb that teaches both
@export var job_xp: Dictionary[StringName, int] = {&"mining": 10}
## Minimum mining level required (legacy: still gated on mining specifically
## for ore veins). Set 0 for non-ore nodes.
@export var required_level: int = 0
## Tool the player must have equipped (matched against ToolItem.tool_type).
@export var required_tool: StringName = &"pickaxe"

@export_group("Extraction")
## HP the per-player progress drains before one charge is consumed and the
## player gets the yield. Each pickaxe swing chips this down by the swing's
## extraction_damage (1 for wooden, more for higher tiers).
@export var extraction_hp: int = 3
## Total shared yields before depletion. Snap-refills as a group, not per-charge.
@export var max_charges: int = 3
## Continuous regen while at least 1 charge remains: +1 charge every X sec.
@export var charge_regen_seconds: float = 12.0
## Recharge time after the node hits 0 charges. Longer than continuous regen,
## refills ALL charges at once so a returning group can mine in parallel
## without racing for the first single charge to reappear.
@export var depleted_recharge_seconds: float = 60.0
## Per-player cooldown after a successful extraction (their progress can't
## start accumulating again until this passes). Keeps a single player from
## solo-vacuuming a full node.
@export var player_cooldown_seconds: float = 5.0

# --- Server-only state ------------------------------------------------------
var _charges: int
## Stamp of the last regen tick. Two meanings depending on _charges:
##   _charges > 0     → time of last continuous regen
##   _charges == 0    → time the node hit empty (waits depleted_recharge_seconds
##                      from this stamp before snap-refilling)
var _last_regen_ms: int
## player_id → remaining extraction HP for that player's current yield.
var _progress_hp_by_player: Dictionary[int, int]
## player_id → ticks_msec at which their cooldown ends.
var _cooldown_until_ms_by_player: Dictionary[int, int]


func _ready() -> void:
	if multiplayer.is_server():
		_charges = max_charges
		_last_regen_ms = Time.get_ticks_msec()
		# Server keeps the node for resolution / proximity; input is
		# swing-driven now so we never need pickable input.
		input_pickable = false
		return
	# Client: no input pickable, no listeners. The pickaxe's swing hitbox
	# drives extraction now. We keep this node around for visual / spatial
	# placement only.
	input_pickable = false


# ---------------------------------------------------------------------------
# Public server API
# ---------------------------------------------------------------------------

## Server-only. Called by PickSwingAbility's hitbox when it overlaps this
## node. Drains the [param player]'s per-extraction HP by [param damage].
## On full drain, consumes a charge, awards items + job XP, returns a result
## the caller can push to the player's client.
##
## Returns the same {"ok": bool, ...} shape the legacy click handler did,
## so existing client toast / gather_succeeded code paths still work.
func register_pickaxe_hit(player: Player, damage: int, instance: ServerInstance) -> Dictionary:
	if ore == null:
		return {"ok": false}
	if player == null or player.player_resource == null:
		return {"ok": false}

	var player_id: int = int(player.player_resource.player_id)
	var now_ms: int = Time.get_ticks_msec()

	# Per-player cooldown: silently soak the swing (no error toast; spamming
	# during cooldown is normal and shouldn't pop notifications).
	if int(_cooldown_until_ms_by_player.get(player_id, 0)) > now_ms:
		return {"ok": false, "reason": "cooldown"}

	# Level gate (still mining-specific for ore veins).
	var mining_skill: Dictionary = player.player_resource.skills.get(MiningPerks.SKILL_NAME, {})
	var mining_level: int = int(mining_skill.get("level", 1))
	var mining_perks: Dictionary = mining_skill.get("perks", {})
	if mining_level < required_level:
		return {"ok": false, "reason": "level", "required_level": required_level}

	# Lazy-regen first so a swing on a depleted node that just timed out
	# refills before we ask for a charge.
	_regen()

	# Drain this player's extraction progress. First hit in a fresh round
	# seeds at extraction_hp; subsequent hits chip down.
	var progress: int = int(_progress_hp_by_player.get(player_id, extraction_hp))
	progress -= maxi(1, damage)

	if progress > 0:
		_progress_hp_by_player[player_id] = progress
		return {
			"ok": true,
			"extracted": false,
			"progress_hp": progress,
			"extraction_hp": extraction_hp,
		}

	# Full drain — try to take a charge. If depleted, no yield; reset their
	# progress so they don't get a "free" first swing when the node refills.
	if _charges <= 0:
		_progress_hp_by_player.erase(player_id)
		return {"ok": false, "extracted": false, "reason": "depleted"}

	_consume_charge(now_ms)
	_progress_hp_by_player.erase(player_id)

	# Award. Mining bonus ore + cooldown discount still ride the mining perk
	# tree; non-mining jobs get vanilla per-job XP for now.
	var amount: int = yield_amount
	if randf() < MiningPerks.effective_bonus_ore_chance(mining_level, mining_perks):
		amount += 1

	var ore_id: int = int(ore.get_meta(&"id", 0))
	Inventory.add_item(player.player_resource.inventory, ore_id, amount)

	# Job XP — iterate the dict so a node can credit multiple jobs at once.
	# Mining's Diligent perk multiplier still applies to mining specifically;
	# other jobs get flat values until they have their own perk trees.
	var grants: Array = []
	for job_name: StringName in job_xp:
		var raw: int = int(job_xp[job_name])
		var xp_gain: int = raw
		if job_name == MiningPerks.SKILL_NAME:
			xp_gain = roundi(raw * MiningPerks.xp_multiplier(mining_perks))
		var prog: Dictionary = player.player_resource.add_skill_xp(job_name, xp_gain)
		grants.append({"job": String(job_name), "xp": xp_gain, "progress": prog})

	# Per-player cooldown after extraction. Shortened by mining baseline +
	# the Efficient Mining perk (matches the old behaviour).
	_cooldown_until_ms_by_player[player_id] = now_ms + int(
		player_cooldown_seconds * 1000.0 * MiningPerks.effective_cooldown_factor(mining_level, mining_perks)
	)

	# Build the "first grant" mining-style payload for backwards-compatible
	# toast / gather_succeeded handling on the client. Multi-job nodes still
	# work, the toast UI just narrates the first one in detail.
	var first: Dictionary = grants[0] if not grants.is_empty() else {}
	var first_progress: Dictionary = first.get("progress", {})
	var first_job: String = first.get("job", "")
	var new_level: int = int(first_progress.get("level", 1))
	var perk_points_gained: int = 0
	if first_job == String(MiningPerks.SKILL_NAME):
		perk_points_gained = MiningPerks.earned_points(new_level) - MiningPerks.earned_points(mining_level)

	return {
		"ok": true,
		"extracted": true,
		"ore_id": ore_id,
		"amount": amount,
		"xp": int(first.get("xp", 0)),
		"job": first_job,
		"level": new_level,
		"leveled_up": first_progress.get("leveled_up", false),
		"perk_points_gained": perk_points_gained,
		"grants": grants,
		"charges_left": _charges,
	}


# ---------------------------------------------------------------------------
# Charge management (server-only)
# ---------------------------------------------------------------------------

func _consume_charge(now_ms: int) -> void:
	_charges -= 1
	if _charges == 0:
		# Mark the depletion time so the longer recharge window starts here.
		_last_regen_ms = now_ms
	elif _charges == max_charges - 1:
		# Just dropped from full → start the continuous regen clock.
		_last_regen_ms = now_ms


## Continuous regen while > 0, snap-refill at == 0. Lazy: only updates on
## access so depleted veins don't burn CPU on a timer.
func _regen() -> void:
	if _charges >= max_charges:
		return
	var now_ms: int = Time.get_ticks_msec()
	if _charges == 0:
		# Depleted state: wait the longer interval, then snap to full.
		if now_ms - _last_regen_ms >= int(depleted_recharge_seconds * 1000.0):
			_charges = max_charges
			_last_regen_ms = now_ms
		return
	# Continuous: tick +1 per interval elapsed (handles long-idle catch-up).
	var regen_ms: int = int(charge_regen_seconds * 1000.0)
	if regen_ms <= 0:
		return
	@warning_ignore("integer_division")
	var gained: int = (now_ms - _last_regen_ms) / regen_ms
	if gained > 0:
		_charges = mini(max_charges, _charges + gained)
		_last_regen_ms += gained * regen_ms


# ---------------------------------------------------------------------------
# Legacy compatibility — kept so anything still calling try_consume_charge
# (e.g. an old debug command) doesn't crash. Prefer register_pickaxe_hit.
# ---------------------------------------------------------------------------

func try_consume_charge() -> bool:
	_regen()
	if _charges <= 0:
		return false
	_consume_charge(Time.get_ticks_msec())
	return true
