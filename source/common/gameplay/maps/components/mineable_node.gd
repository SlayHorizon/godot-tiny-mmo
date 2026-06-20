class_name MineableNode
extends Area2D
## A world-space gathering node (ore vein, herb patch, etc.). v2: swing-based.
## A pickaxe swing's hitbox overlaps this Area2D → register_gather_hit fires
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
## - **Job XP routing**: data.job_xp is a dict so a healing herb can grant
##   both harvesting AND medicine; an ore vein just grants mining.
##
## Setup: instance mineable_node.tscn under the Map, assign a
## [MineableNodeResource] on [member data], position it. Identity is the
## node's Godot-unique name within the Map.

## Defines what this node IS (ore type, yields, XP grants, timings).
## Assign a `.tres` from `source/common/gameplay/maps/components/mineable_nodes/`.
@export var data: MineableNodeResource

# --- Cached refs ------------------------------------------------------------
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _bar: ProgressBar = $VisualState/ProgressBar
@onready var _charge_label: Label = $VisualState/ChargeLabel
@onready var _visual_state: Control = $VisualState

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

# --- Client-only charge prediction -----------------------------------------
# The server reports the authoritative charge count on each swing result, but
# between swings nobody pushes regen updates, so the label would read a stale
# "0/3" until the next hit. Since the regen timings live on `data` (shared by
# client + server), the client can predict the tick-up locally and keep the
# label live. -1 = no state received yet.
var _disp_charges: int = -1
var _disp_max: int
## Predicted ticks_msec of the next charge gain (or full snap-refill at 0).
var _next_regen_ms: int


func _ready() -> void:
	collision_layer = PhysicsLayers.HARVESTABLE # pick/sickle arcs target this to gather
	if data == null:
		push_warning("MineableNode '%s' has no data resource assigned." % name)
		return

	# Apply visuals on every peer (server included; harmless and keeps the
	# editor's preview honest).
	_apply_sprite()
	_visual_state.visible = false
	# Lift the progress bar + charge label above map decorations (plants, rocks)
	# that otherwise render on top of this node's world-space Control.
	_visual_state.z_index = 100

	if multiplayer.is_server():
		_charges = data.max_charges
		_last_regen_ms = Time.get_ticks_msec()
	# Input is swing-driven now — the pickaxe's hitbox drives extraction, so
	# this Area2D never needs pickable input on either side.
	input_pickable = false
	# Charge prediction only runs once a client receives state and arms it.
	set_process(false)


# ---------------------------------------------------------------------------
# Public server API
# ---------------------------------------------------------------------------

## Server-only. Called by a tool's swing hitbox (PickArc) when it overlaps
## this node. Drains the [param player]'s per-extraction HP by [param damage].
## On full drain, consumes a charge, awards items + job XP, returns a result
## the caller can push to the player's client.
##
## Generic across gather types (ore veins, herb patches, etc.). The
## mining-specific perk tree (level gate, bonus-ore chance, XP multiplier,
## cooldown discount) only applies when this node's primary job is mining.
##
## Returns {"ok": bool, ...}. On success the dict also carries a
## `node_path` so the client can route per-node visual state updates.
func register_gather_hit(player: Player, damage: int, instance: ServerInstance, tool_type: StringName = &"") -> Dictionary:
	if data == null or data.ore == null:
		return {"ok": false}
	if player == null or player.player_resource == null:
		return {"ok": false}

	var player_id: int = int(player.player_resource.player_id)
	var now_ms: int = Time.get_ticks_msec()
	var node_path: NodePath = instance.get_path_to(self)

	# Wrong-tool gate: a node worked by the wrong tool (e.g. a pickaxe on a herb
	# that needs a sickle) yields nothing and tells the client which tool to
	# equip. Checked before the cooldown soak so the hint always reaches the
	# player even mid-cooldown. A node with no required_tool accepts any tool.
	if data.required_tool != &"" and tool_type != data.required_tool:
		return {
			"ok": false,
			"extracted": false,
			"reason": "wrong_tool",
			"required_tool": String(data.required_tool),
			"node_path": node_path,
		}

	# Per-player cooldown: silently soak the swing (no error toast; spamming
	# during cooldown is normal and shouldn't pop notifications).
	if int(_cooldown_until_ms_by_player.get(player_id, 0)) > now_ms:
		return {"ok": false, "reason": "cooldown"}

	# Mining-tree gates only apply to mining nodes. The check is "is mining
	# in this node's job_xp dict" — that lets a future "ore that also grants
	# smithing XP" still respect mining level/perks while keeping herbs
	# free of mining bias.
	var is_mining_node: bool = data.job_xp.has(&"mining")
	var mining_perks_resource: JobPerks = JobRegistry.perks_for(&"mining")
	var mining_level: int = 1
	var mining_perks: Dictionary = {}
	if is_mining_node:
		var mining_skill: Dictionary = player.player_resource.skills.get(&"mining", {})
		mining_level = int(mining_skill.get("level", 1))
		mining_perks = mining_skill.get("perks", {})
		if mining_level < data.required_level:
			return {"ok": false, "reason": "level", "required_level": data.required_level}

	# Lazy-regen first so a swing on a depleted node that just timed out
	# refills before we ask for a charge.
	_regen()

	# Depleted nodes reject the swing outright — we drain nothing so the
	# client never shows a teasing progress bar on a vein that can't yield.
	# The 0/N charge label + client-side regen prediction tell the player to
	# come back later. (Checked here, before draining, so a fresh swinger
	# doesn't get the first few "free" progress ticks on an empty node.)
	if _charges <= 0:
		_progress_hp_by_player.erase(player_id)
		return {
			"ok": false,
			"extracted": false,
			"reason": "depleted",
			"charges_left": 0,
			"max_charges": data.max_charges,
			"node_path": node_path,
		}

	# Drain this player's extraction progress. First hit in a fresh round
	# seeds at data.extraction_hp; subsequent hits chip down.
	var progress: int = int(_progress_hp_by_player.get(player_id, data.extraction_hp))
	progress -= maxi(1, damage)

	if progress > 0:
		_progress_hp_by_player[player_id] = progress
		return {
			"ok": true,
			"extracted": false,
			"progress_hp": progress,
			"extraction_hp": data.extraction_hp,
			"charges_left": _charges,
			"max_charges": data.max_charges,
			"node_path": node_path,
		}

	# Full drain — consume a charge (guaranteed > 0 by the early reject above).
	_consume_charge(now_ms)
	_progress_hp_by_player.erase(player_id)

	# Award. Bonus-yield + cooldown discount come from the mining perk tree
	# and only apply to mining nodes (gated by is_mining_node above).
	var amount: int = data.yield_amount
	if is_mining_node and mining_perks_resource != null \
			and randf() < mining_perks_resource.effective_bonus_yield_chance(mining_level, mining_perks):
		amount += 1

	var ore_id: int = int(data.ore.get_meta(&"id", 0))
	Inventory.add_item(player.player_resource.inventory, ore_id, amount)

	# Job XP — iterate the dict so a node can credit multiple jobs at once.
	var grants: Array = []
	for job_name: StringName in data.job_xp:
		var raw: int = int(data.job_xp[job_name])
		var xp_gain: int = raw
		var jp: JobPerks = JobRegistry.perks_for(job_name)
		if jp != null:
			var job_skill: Dictionary = player.player_resource.skills.get(job_name, {})
			var job_perks_dict: Dictionary = job_skill.get("perks", {})
			xp_gain = roundi(raw * jp.xp_multiplier(job_perks_dict))
		var prog: Dictionary = player.player_resource.add_skill_xp(job_name, xp_gain)
		grants.append({"job": String(job_name), "xp": xp_gain, "progress": prog})

	# Per-player cooldown after extraction. Shortened by mining perks on
	# mining nodes; flat duration otherwise.
	var cooldown_factor: float = 1.0
	if is_mining_node and mining_perks_resource != null:
		cooldown_factor = mining_perks_resource.effective_cooldown_factor(mining_level, mining_perks)
	_cooldown_until_ms_by_player[player_id] = now_ms + int(
		data.player_cooldown_seconds * 1000.0 * cooldown_factor
	)

	# Build the "first grant" mining-style payload for backwards-compatible
	# toast / gather_succeeded handling on the client.
	var first: Dictionary = grants[0] if not grants.is_empty() else {}
	var first_progress: Dictionary = first.get("progress", {})
	var first_job: String = first.get("job", "")
	var new_level: int = int(first_progress.get("level", 1))
	var perk_points_gained: int = 0
	if is_mining_node and mining_perks_resource != null and first_job == "mining":
		perk_points_gained = mining_perks_resource.earned_points(new_level) - mining_perks_resource.earned_points(mining_level)

	return {
		"ok": true,
		"extracted": true,
		"ore_id": ore_id,
		"ore_name": String(data.ore.item_name),
		"amount": amount,
		"xp": int(first.get("xp", 0)),
		"job": first_job,
		"level": new_level,
		"leveled_up": first_progress.get("leveled_up", false),
		"perk_points_gained": perk_points_gained,
		"grants": grants,
		"progress_hp": 0,
		"extraction_hp": data.extraction_hp,
		"charges_left": _charges,
		"max_charges": data.max_charges,
		"node_path": node_path,
	}


# ---------------------------------------------------------------------------
# Client-side visual state — called by [member ClientState] when a gather
# result comes in for THIS node. Only the player who swung will hit this
# path; others see stale visuals until they swing it themselves. Acceptable
# for prototype; broadcast can come later.
# ---------------------------------------------------------------------------

## Client-only. Updates the progress bar (extraction progress) and hands the
## charge count to the predictor, which owns the charge label and ticks it
## back up over time. Two independent visibilities so the bar isn't lingering
## "full" after a yield while the charge label keeps reading the partial state:
##   - Bar:    only while mid-extraction (0 < progress < extraction_hp).
##             Drains like mob HP (extraction_hp → 0), then hides on yield.
##   - Charge: only when the vein is partially depleted (charges < max), and
##             predicted forward by [method _process] between swings.
func apply_visual_state(progress_hp: int, extraction_hp: int, charges: int, max_charges: int) -> void:
	if _visual_state == null:
		return
	var mid_extraction: bool = progress_hp > 0 and progress_hp < extraction_hp
	_bar.visible = mid_extraction
	if mid_extraction:
		_bar.max_value = maxi(1, extraction_hp)
		_bar.value = progress_hp
	_set_displayed_charges(charges, max_charges)


# ---------------------------------------------------------------------------
# Client-only charge prediction
# ---------------------------------------------------------------------------

func _set_displayed_charges(charges: int, max_charges: int) -> void:
	_disp_charges = charges
	_disp_max = max_charges
	_arm_regen_prediction()
	_refresh_charge_label()


## Schedules the next predicted regen tick from the shared `data` timings,
## mirroring the server's lazy [method _regen] (continuous +1 while > 0, a
## single snap-refill to full from 0). Disables prediction when already full.
func _arm_regen_prediction() -> void:
	if data == null or _disp_charges < 0 or _disp_charges >= _disp_max:
		set_process(false)
		return
	var interval_s: float = data.depleted_recharge_seconds if _disp_charges <= 0 else data.charge_regen_seconds
	_next_regen_ms = Time.get_ticks_msec() + int(interval_s * 1000.0)
	set_process(true)


func _process(_delta: float) -> void:
	if _disp_charges < 0 or _disp_charges >= _disp_max:
		set_process(false)
		return
	if Time.get_ticks_msec() < _next_regen_ms:
		return
	if _disp_charges <= 0:
		_disp_charges = _disp_max  # depleted nodes snap-refill all at once
	else:
		_disp_charges += 1
	_arm_regen_prediction()
	_refresh_charge_label()


func _refresh_charge_label() -> void:
	if _visual_state == null:
		return
	var partial: bool = _disp_charges >= 0 and _disp_charges < _disp_max
	_charge_label.visible = partial
	_visual_state.visible = _bar.visible or partial
	if partial:
		_charge_label.text = "%d / %d" % [_disp_charges, _disp_max]


# ---------------------------------------------------------------------------
# Charge management (server-only)
# ---------------------------------------------------------------------------

func _consume_charge(now_ms: int) -> void:
	_charges -= 1
	if _charges == 0:
		# Mark the depletion time so the longer recharge window starts here.
		_last_regen_ms = now_ms
	elif _charges == data.max_charges - 1:
		# Just dropped from full → start the continuous regen clock.
		_last_regen_ms = now_ms


## Continuous regen while > 0, snap-refill at == 0. Lazy: only updates on
## access so depleted veins don't burn CPU on a timer.
func _regen() -> void:
	if _charges >= data.max_charges:
		return
	var now_ms: int = Time.get_ticks_msec()
	if _charges == 0:
		# Depleted state: wait the longer interval, then snap to full.
		if now_ms - _last_regen_ms >= int(data.depleted_recharge_seconds * 1000.0):
			_charges = data.max_charges
			_last_regen_ms = now_ms
		return
	# Continuous: tick +1 per interval elapsed (handles long-idle catch-up).
	var regen_ms: int = int(data.charge_regen_seconds * 1000.0)
	if regen_ms <= 0:
		return
	@warning_ignore("integer_division")
	var gained: int = (now_ms - _last_regen_ms) / regen_ms
	if gained > 0:
		_charges = mini(data.max_charges, _charges + gained)
		_last_regen_ms += gained * regen_ms


# ---------------------------------------------------------------------------
# Sprite plumbing — read texture + region from data on _ready. Region is
# applied only when set (zero-sized rect = full texture).
# ---------------------------------------------------------------------------

func _apply_sprite() -> void:
	if data == null or data.texture == null:
		return
	# Works whether `data.texture` is a plain Texture2D or an AtlasTexture —
	# AtlasTexture is itself a Texture2D and carries its own region.
	_sprite.texture = data.texture
