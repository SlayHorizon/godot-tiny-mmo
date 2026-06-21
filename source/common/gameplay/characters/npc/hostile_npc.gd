@tool
class_name HostileNpc
extends Character


enum EnemyState {
	RETURNING,
	IDLE,
	CHASE,
	ATTACK,
	DEAD,
	# Appended (don't reorder — the int value is state-synced to clients):
	LUNGE_WINDUP, ## planted, telegraphing the pounce zone
	LUNGING,      ## dashing to the locked spot
}

## Flip to true to dump every meaningful NPC state transition. Server lines
## use [SRV NPC <type>] tags, client lines use [CLI NPC <type>] — grep one
## or the other in journalctl / the editor console depending on which side
## you're investigating. Leave off in normal play; the printerr volume
## scales with NPC count. (Was used to nail the chase_on_area zombie bug —
## kept wired so the next mystery is one constant flip away.)
const DEBUG_NPC: bool = false

## How fast a RETURNING NPC moves vs its normal speed. Leashed mobs need
## to outrun any reasonable kiting pace, otherwise a ranged player can
## drag them home in slow motion while still in their max chase range.
const RETURN_SPEED_MULTIPLIER: float = 1.4

## % of max HP regenerated per second while RETURNING. At 0.25 a mob at
## near-zero HP fully heals over ~4s of walking. Reads visibly on the bar
## without being instant.
const RETURN_REGEN_RATE: float = 0.25

## % of max HP regenerated per second while idling — catches the edge case
## of a sniped mob taking damage from outside its detection ring, since
## that hit can't trigger CHASE if the attacker stays out of range. ~5%/s
## means a mob recovers from a missed snipe over 5-10 seconds.
const IDLE_REGEN_RATE: float = 0.05

## A mob holds still (AI suspended via action_root_until_ms) for this long on spawn / respawn so the
## summon burst reads on a still body instead of a mob blinking in mid-stride.
const SPAWN_FREEZE_S: float = 0.5



## Toggle in the inspector to render the leash + detection rings around
## this NPC. The script is @tool so the circles appear in-editor as soon
## as you flick this on — no need to run the scene. The setter calls
## queue_redraw so it updates the moment you tick the box.
@export var debug_draw_ranges: bool = false:
	set(value):
		debug_draw_ranges = value
		queue_redraw()

## Emitted server-side whenever this NPC takes damage from a real attacker.
## Other HostileNpcs inside this one's detection_area subscribe via
## body_entered, so a pack reacts as a unit when one of them gets hit.
## Decoupled via signal so we never need a direct "list of allies" array
## that has to be maintained / cleaned up.
signal was_attacked(attacker: Character)

## Data-driven definition. REQUIRED: every HostileNpc instance must point at an
## EnemyTypeResource. All combat/AI fields below are populated from it at
## _ready, so per-instance inspector tweaks are deliberately not supported —
## edit the .tres if you want to change behaviour, and every spawn of that
## archetype picks up the change. Per-instance overrides invite the exact
## "enemy_type says 'mobs' but the kill registers as 'bandit'" confusion we
## just cleaned up.
@export var enemy_data: EnemyTypeResource

## ContentRegistry `enemy_types` slug of this NPC's archetype. Setting it resolves
## [member enemy_data] from the registry — lets a dynamically-spawned NPC (e.g. a
## guild guard) carry its archetype over the wire as a short slug instead of a
## resource path. Applied BEFORE add_child on both sides so _ready sees
## enemy_data. Authored mobs set enemy_data directly and leave this empty.
var enemy_type_slug: StringName = &"":
	set(value):
		enemy_type_slug = value
		if value != &"":
			var data: EnemyTypeResource = ContentRegistryHub.load_by_slug(&"enemy_types", value) as EnemyTypeResource
			if data != null:
				enemy_data = data

## Owning guild / faction (0 = none). When > 0 this NPC is a guild defender: it
## ignores players tagged into that guild and is single-life (despawns on death,
## no respawn). Set on spawn by the flag (server-only — clients just render).
var owner_guild_id: int = 0

## Server-only aggro trigger. Built programmatically in _ready (server)
## from max_distance_from_spawn × DETECTION_RADIUS_FACTOR — no scene
## wiring, no client-side cost. The radius is the only meaningful tuning
## knob here; if you ever want a non-circular detection (cone, vision),
## swap the CollisionShape2D's shape after construction.
var detection_area: Area2D

# --- Driven by enemy_data (do NOT @export, see class docstring above) ---
# Their defaults below act only as fallbacks if enemy_data is somehow missing
# (we assert against that in _apply_enemy_data), so authoring lives entirely
# in the .tres files under characters/npc/types/.

## Identifier used by quest KILL objectives (e.g. &"slime"). Enemies sharing a
## type count toward the same objective.
var enemy_type: StringName
var max_health: float = 50.0
var attack_damage: float = 8.0
## Seconds between auto-attacks while in range.
var attack_cooldown: float = 1.5
var armor: float = 0.0
var mr: float = 0.0
## Optional weapon. If set, the enemy equips it and fires its ability at the
## target (reusing the same projectiles players use). If null, the enemy is a
## melee AoE attacker. Exported as a PER-NODE OVERRIDE: leave empty to use the
## EnemyTypeResource's weapon; set it on a placed node to arm just that one
## (an archer in a melee camp) without touching the shared .tres.
@export var weapon: WeaponItem
var xp_reward: int = 25
## peer_id -> total damage dealt this life (cleared on respawn). Drives the
## participation reward split — see RewardService.
var _contributors: Dictionary[int, float] = {}
## Whether this mob respawns after death (driven by enemy_data.respawns). False =
## single-life: the body is removed, no return (dungeon mobs, one-off bosses).
var respawns: bool = true

## Emitted on death, server-side. The CONTEXT that spawned the mob wires the
## consequence — a dungeon connects its boss's `died` → clear; a world-boss event
## connects it → its own handler. Keeps death-consequences OUT of the mob class.
signal died(killer: Character)

## Leash radius used to mean "infinite" — set when enemy_data.leashes is false so
## the mob commits and fights to the death instead of walking home.
const NO_LEASH_DISTANCE: int = 1_000_000
## Seconds before a killed enemy respawns at its spawn point.
var respawn_delay: float = 5.0
var loot: Array[LootDrop]
var move_speed: int = 20
## Distance to the player at which the NPC switches from CHASE to ATTACK.
var distance_to_attack: int = 20
## If the NPC strays this far from its spawn, it disengages and returns.
var max_distance_from_spawn: int = 300
## Aggro radius — how far the mob "sees". Must be smaller than the leash
## so the mob can reach anything it spots before the leash trips. Driven
## by enemy_data.detection_radius.
var detection_radius: int = 150
## Start chasing as soon as a player steps inside detection_area.
var chase_on_area: bool = false
## Telegraphed lunge knobs (see EnemyTypeResource). lunge_range 0 = never lunges.
var lunge_range: float = 0.0
var lunge_radius: float = 24.0
var lunge_windup_s: float = 0.55
var lunge_speed_multiplier: float = 5.0
var lunge_cooldown: float = 5.0

## Where the pounce will land — locked at windup start, NOT homing (that's what
## makes it dodgeable).
var _lunge_target_position: Vector2
## Dash heading, locked at windup start — the dash flies STRAIGHT, never
## re-aims mid-flight (re-aiming is what made it jitter around a point it
## couldn't reach when that point sat inside the player's collider).
var _lunge_direction: Vector2
var _lunge_phase_until_ms: int
var _lunge_deadline_ms: int
var _lunge_ready_at_ms: int
## Players already hit by the CURRENT dash (instance id -> true) — the sweep
## damages anyone the dash runs over, but each victim only once per lunge.
var _lunge_hit: Dictionary = {}


## Copy archetype fields onto this instance. Called once at _ready so the rest
## of HostileNpc can keep reading its local fields unchanged.
func _apply_enemy_data() -> void:
	assert(enemy_data != null, "HostileNpc requires an enemy_data resource — see characters/npc/types/.")
	enemy_type = enemy_data.enemy_type
	display_name = enemy_data.display_name # drives the shared over-head name label
	max_health = enemy_data.max_health
	attack_damage = enemy_data.attack_damage
	attack_cooldown = enemy_data.attack_cooldown
	armor = enemy_data.armor
	mr = enemy_data.mr
	if weapon == null: # node-level override wins; resource is the default
		weapon = enemy_data.weapon
	xp_reward = enemy_data.xp_reward
	respawn_delay = enemy_data.respawn_delay
	loot = enemy_data.loot
	move_speed = enemy_data.move_speed
	distance_to_attack = enemy_data.distance_to_attack
	max_distance_from_spawn = enemy_data.max_distance_from_spawn
	respawns = enemy_data.respawns
	# A non-leashing mob (bosses; trash in bounded dungeon rooms) commits — an
	# effectively-infinite leash so the distance check never walks it home.
	if not enemy_data.leashes:
		max_distance_from_spawn = NO_LEASH_DISTANCE
	detection_radius = enemy_data.detection_radius
	chase_on_area = enemy_data.chase_on_area
	lunge_range = enemy_data.lunge_range
	lunge_radius = enemy_data.lunge_radius
	lunge_windup_s = enemy_data.lunge_windup_s
	lunge_speed_multiplier = enemy_data.lunge_speed_multiplier
	lunge_cooldown = enemy_data.lunge_cooldown
	if enemy_data.skin != null:
		skin_id = 0 # disable id-based skin; we're driving it directly
		# animated_sprite (from Character) is @onready — already assigned by the
		# time _ready (and therefore this) runs.
		animated_sprite.sprite_frames = enemy_data.skin
	# Visual size (a boss reads bigger) — SPRITE only, never the node (a scaled
	# node inflates collision so it can't reach melee range). Applied on both
	# server + client since enemy_data resolves on both.
	if enemy_data.visual_scale != 1.0:
		animated_sprite.scale *= enemy_data.visual_scale
		# A big sprite swallows the head-bar — lift it clear of the enlarged sprite
		# and scale it up so a boss reads as a boss. Scale around the bar's own
		# centre so it stays horizontally centred over the mob.
		if has_node(^"ProgressBar"):
			var bar: Control = $ProgressBar
			var lift: float = 55.0 * (enemy_data.visual_scale - 1.0)
			bar.offset_top -= lift
			bar.offset_bottom -= lift
			bar.pivot_offset = Vector2(
				(bar.offset_right - bar.offset_left) * 0.5,
				(bar.offset_bottom - bar.offset_top) * 0.5
			)
			bar.scale = Vector2.ONE * enemy_data.visual_scale

var container: ReplicatedPropsContainer
var enemy_state: EnemyState = EnemyState.IDLE

var possible_targets: Array[Player]
var targeted_player: Player
var spawn_position: Vector2

var _prop_id: int
var _position_fid: int
var _anim_fid: int
var _state_fid: int
var _health_fid: int
var _health_max_fid: int
## When (Time.get_ticks_msec) a dead enemy should respawn.
var _respawn_at_ms: int
## When the next auto-attack is allowed.
var _next_attack_ms: int


func _ready() -> void:
	# Editor mode (we're @tool for the debug-draw export): skip everything
	# runtime, just nudge a redraw so the inspector toggle takes effect.
	if Engine.is_editor_hint():
		queue_redraw()
		return
	# Pull archetype values from enemy_data BEFORE Character._ready reads any
	# stats — so a data-driven NPC's @exports already reflect the resource.
	_apply_enemy_data()
	# Character._ready wires the client-side health bar (stat_changed -> ProgressBar);
	# without this the NPC's bar is never initialised or connected. On the server it
	# returns immediately.
	super._ready()
	# Equip the weapon on both server (to fire/deal damage) and client (visual + to
	# replay the shot). Done before the stat init below so the explicit NPC stats win.
	_equip_weapon()
	assert(get_parent() is ReplicatedPropsContainer, "HostileNPC must be a child of ReplicatedPropContainer.")
	if not multiplayer.is_server():
		# Client-side diagnostic: log every HEALTH / HEALTH_MAX value that
		# comes off the synchronizer wire, so we can see whether the bar
		# being empty reflects what the server actually sent. Server-side
		# transitions live in their own [SRV NPC ...] prints.
		if DEBUG_NPC:
			stats_component.stats.stat_changed.connect(_debug_client_stat_changed)
		_apply_ally_bar_tint()
		# Re-evaluate if the local player's guild changes (so a guard that spawned
		# before you tagged in updates without a relog).
		if is_instance_valid(ClientState):
			ClientState.active_guild_id_changed.connect(_on_local_guild_changed)
		set_physics_process(false)
		return
	
	# Build the detection trigger here so the scene is lean (no Area2D node
	# shipped to clients for nothing) and the radius can be derived from
	# the leash distance — single source of truth, can't drift.
	_build_detection_area()
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

	spawn_position = global_position
	container = get_parent()

	_prop_id = container.child_id_of_node(self)
	_position_fid = PathRegistry.ensure_id(^":position")
	_anim_fid = PathRegistry.ensure_id(^":anim")
	_state_fid = PathRegistry.register_field(":enemy_state", Wire.Type.VARIANT)
	_health_fid = PathRegistry.ensure_id("StatsComponent:stats:health")
	_health_max_fid = PathRegistry.ensure_id("StatsComponent:stats:health_max")

	# Server-authoritative combat stats.
	stats_component.set_stat(Stat.HEALTH_MAX, max_health)
	stats_component.set_stat(Stat.HEALTH, max_health)
	stats_component.set_stat(Stat.AD, attack_damage)
	# AP mirrors AD so a magic weapon (wand bolt scales off AP) hits with the
	# same tuned attack_damage as any other armament — mob power is ONE number.
	stats_component.set_stat(Stat.AP, attack_damage)
	stats_component.set_stat(Stat.ARMOR, armor)
	stats_component.set_stat(Stat.MR, mr)

	# Push the full initial state (position especially) in the SPAWN tick, so a freshly-spawned mob
	# is placed correctly on clients immediately instead of sitting at the container origin until
	# its first physics frame. Without this, a spawn VFX fired right after spawn lands at (0,0).
	_process_synchronization()


func _on_local_guild_changed(_new_id: int) -> void:
	_apply_ally_bar_tint()


## Client-only: a guild guard's HP bar reads blue to guildmates (ally) and red to
## everyone else; ally guards also stay visible. Regular mobs keep the default
## hostile color from Character._ready. Idempotent (re-runs on guild change).
func _apply_ally_bar_tint() -> void:
	if multiplayer.is_server() or owner_guild_id <= 0:
		return
	var is_ally: bool = is_instance_valid(ClientState) and ClientState.active_guild_id == owner_guild_id
	set_health_bar_fill(BAR_COLOR_ALLY if is_ally else BAR_COLOR_HOSTILE)
	if is_ally and has_node(^"ProgressBar"):
		($ProgressBar as CanvasItem).show() # ally guards stay visible


## Server-set: while this timestamp is in the future the body holds position — a
## BossController commits it to a telegraphed cast instead of strolling out of its
## own danger ring. Generic, like the lunge windup's root but driven from outside
## the state machine.
var action_root_until_ms: int = 0


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not multiplayer.is_server():
		return

	# Rooted for a telegraphed cast: hold position. DEAD still processes so death
	# isn't deferred behind the wind-up.
	if enemy_state != EnemyState.DEAD and Time.get_ticks_msec() < action_root_until_ms:
		velocity = Vector2.ZERO
		return

	match enemy_state:
		EnemyState.RETURNING:
			_process_return()
		EnemyState.IDLE:
			_process_idle_regen()
		EnemyState.CHASE:
			_process_chase()
		EnemyState.ATTACK:
			_process_attack()
		EnemyState.DEAD:
			_process_death()
		EnemyState.LUNGE_WINDUP:
			_process_lunge_windup()
		EnemyState.LUNGING:
			_process_lunging()

	_find_targets()
	_process_animations()
	_process_synchronization()


func _on_body_entered(body: Node) -> void:
	# Ally-pack assist: when another HostileNpc enters detection range,
	# subscribe to their was_attacked signal so we aggro the attacker
	# alongside them. Mob types that should be lone wolves can set
	# is_lone=true on their EnemyTypeResource to opt out.
	if body is HostileNpc and body != self:
		if not (body as HostileNpc).was_attacked.is_connected(_on_ally_attacked):
			(body as HostileNpc).was_attacked.connect(_on_ally_attacked)
		return

	if body is not Player: return
	if not _is_hostile_to(body): return # Defenders ignore their own guild.

	if possible_targets.has(body):
		possible_targets.set(possible_targets.find(body, 0), body)
	else:
		possible_targets.append(body)

	# CRITICAL: don't yank a dead NPC out of DEAD state into CHASE. Without
	# this, a player walking back into the detection area during the respawn
	# timer flips enemy_state → CHASE, _process_death never runs, is_dead and
	# HEALTH=0 get stuck forever, and every subsequent take_damage early-
	# returns. That's the "zombie NPC" symptom (empty bar, no kill credit,
	# happens only for chase_on_area=true mobs). _find_targets already has
	# the same DEAD guard — this one was just missing.
	if DEBUG_NPC and enemy_state == EnemyState.DEAD and chase_on_area:
		printerr("[SRV NPC %s] body_entered while DEAD — guard prevented zombie" % enemy_type)
	if chase_on_area and not targeted_player and enemy_state != EnemyState.DEAD:
		targeted_player = body
		enemy_state = EnemyState.CHASE
		if DEBUG_NPC:
			printerr("[SRV NPC %s] body_entered → CHASE (target=%s)" % [enemy_type, body.name])


func _on_body_exited(body: Node) -> void:
	if body is HostileNpc and body != self:
		if (body as HostileNpc).was_attacked.is_connected(_on_ally_attacked):
			(body as HostileNpc).was_attacked.disconnect(_on_ally_attacked)
		return

	if body is not Player: return
	if body == targeted_player: return

	possible_targets.erase(body)


## A nearby ally got hit by [param attacker]. If we're free to engage,
## switch target to the attacker so a pack of mobs aggros together when
## one of them is poked. Skipped while RETURNING / DEAD so leash + respawn
## flows stay clean, and skipped if we already have a target so we don't
## thrash between attackers.
func _on_ally_attacked(attacker: Character) -> void:
	if is_dead:
		return
	if enemy_state == EnemyState.DEAD or enemy_state == EnemyState.RETURNING:
		return
	if targeted_player != null:
		return
	if attacker is Player and not (attacker as Player).is_dead and _is_hostile_to(attacker as Player):
		targeted_player = attacker as Player
		enemy_state = EnemyState.CHASE


func _find_targets() -> void:
	if targeted_player: return
	if enemy_state == EnemyState.RETURNING or enemy_state == EnemyState.DEAD: return

	# Self-heal the cached list against the physics truth first: a player who never
	# LEFT the area after we dropped them is invisible to us otherwise. stop_chase
	# erases the old target, and body_entered only fires on a boundary CROSSING — so
	# a player we de-aggroed (leash, respawn) while they stood in range never gets
	# re-added. That's the long-standing "can't re-aggro by standing there, but
	# hitting me works (take_damage sets the target directly)" bug.
	_resync_possible_targets()

	# First living player still in range (skips dead/freed entries). Re-acquires
	# players who were already inside the area after a respawn.
	for candidate: Player in possible_targets:
		if _is_target_valid(candidate) and _is_hostile_to(candidate):
			targeted_player = candidate
			enemy_state = EnemyState.CHASE
			return


## Fold any player currently overlapping our detection area back into
## possible_targets. Additions only — body_exited handles removals. Cheap (a
## handful of bodies) and only runs while we're hunting (no target, not returning).
func _resync_possible_targets() -> void:
	if detection_area == null:
		return
	for body: Node2D in detection_area.get_overlapping_bodies():
		if body is Player and _is_hostile_to(body) and not possible_targets.has(body):
			possible_targets.append(body)


## Defenders are hostile to everyone EXCEPT players tagged into their owning
## guild. Regular mobs are hostile to all players.
func _is_hostile_to(player: Player) -> bool:
	if owner_guild_id <= 0:
		return true # Ordinary mob — hostile to every player.
	if player == null or player.player_resource == null:
		return true
	return player.player_resource.active_guild_id != owner_guild_id


## Valid = a living player still in THIS instance. Catches warp-outs: a warped
## player is reparented to another instance (different viewport, or briefly no
## parent mid-transfer), so the guard drops the target and heads home instead of
## chasing into the void.
func _is_target_valid(player: Player) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() \
			and not player.is_dead and player.get_viewport() == get_viewport()


## A player can't MOVE more than a couple of px per physics tick — a bigger jump
## means they TELEPORTED (death respawn, warp, /goto, spar start...). Server-side
## death + respawn happens within one frame, so is_dead is never observably true;
## perceiving the position discontinuity is the intuitive, mechanism-agnostic way
## to notice "my prey vanished" instead of marching across the map to the respawn.
const TARGET_TELEPORT_BREAK_PX: float = 60.0
var _tracked_target: Player
var _tracked_target_position: Vector2


func _target_escaped() -> bool:
	if targeted_player != _tracked_target:
		# New target — start tracking from wherever they are now.
		_tracked_target = targeted_player
		_tracked_target_position = targeted_player.global_position
		return false
	var jump: float = _tracked_target_position.distance_to(targeted_player.global_position)
	_tracked_target_position = targeted_player.global_position
	return jump > TARGET_TELEPORT_BREAK_PX


# --- Telegraphed lunge -------------------------------------------------------

## Lock the pounce at the target's CURRENT position (not homing — that's the
## dodge), show the zone on every client, and start the windup.
func _begin_lunge() -> void:
	# Charge THROUGH the target's spot, not TO it: the landing point overshoots
	# behind the player (relative to us), so backing straight away stays inside
	# the corridor — the only real dodge is stepping OUT of it sideways. Also
	# keeps the landing point out of the player's collider.
	_lunge_direction = global_position.direction_to(targeted_player.global_position)
	_lunge_target_position = targeted_player.global_position + _lunge_direction * (lunge_radius * 2.0)
	_lunge_phase_until_ms = Time.get_ticks_msec() + int(lunge_windup_s * 1000.0)
	enemy_state = EnemyState.LUNGE_WINDUP
	velocity = Vector2.ZERO
	_lunge_hit.clear()
	# Corridor telegraph (wolf → landing spot) so players see WHO is charging
	# and which strip of ground to vacate. Lives through windup + travel time.
	container.queue_op(_prop_id, "rp_lunge_telegraph", [
		_lunge_target_position, lunge_radius, lunge_windup_s + 0.45
	])


func _process_lunge_windup() -> void:
	if Time.get_ticks_msec() >= _lunge_phase_until_ms:
		enemy_state = EnemyState.LUNGING
		# Safety deadline: a wall-stuck pounce lands where it got stuck instead
		# of dashing forever.
		_lunge_deadline_ms = Time.get_ticks_msec() + 1200


func _process_lunging() -> void:
	# Straight-line dash with the heading locked at windup. Termination is by
	# PROJECTION onto that heading — once we reach or pass the landing plane
	# (even after sliding around a collider) the dash is over. No re-aiming →
	# no jitter, ever.
	var remaining: float = (_lunge_target_position - global_position).dot(_lunge_direction)
	if remaining <= 8.0 or Time.get_ticks_msec() >= _lunge_deadline_ms:
		_land_lunge()
		return
	velocity = _lunge_direction * move_speed * lunge_speed_multiplier
	move_and_slide()
	# The DASH is the attack: anyone the wolf runs over inside the corridor
	# takes the hit (once per lunge). Per-tick distance check is sweep-safe —
	# at ~5px of travel per physics tick the radius can't tunnel past a player.
	var damage: float = stats_component.get_stat(Stat.AD)
	for candidate: Player in _strike_candidates():
		if _lunge_hit.has(candidate.get_instance_id()):
			continue
		if _is_target_valid(candidate) and _is_hostile_to(candidate) \
				and global_position.distance_to(candidate.global_position) <= lunge_radius:
			_lunge_hit[candidate.get_instance_id()] = true
			candidate.take_damage(damage, self)


## Touchdown: start the cooldown and hand control back to the normal brain.
## (Damage already happened in-flight — the dash itself is the hitbox.)
func _land_lunge() -> void:
	_lunge_ready_at_ms = Time.get_ticks_msec() + int(lunge_cooldown * 1000.0)
	# The windup+dash took ~a second — the target legitimately moved meanwhile.
	# Reset the escape tracker so that movement isn't misread as a teleport.
	_tracked_target = null
	if _is_target_valid(targeted_player):
		enemy_state = EnemyState.CHASE
	else:
		_abandon_target()


## Client-visual: the red dodge corridor from this wolf to the locked landing
## spot — shows WHO is charging and the exact strip of ground to vacate.
func rp_lunge_telegraph(to_position: Vector2, radius: float, duration: float) -> void:
	if multiplayer.is_server():
		return
	var telegraph: AttackTelegraph = AttackTelegraph.new()
	telegraph.radius = radius
	telegraph.duration = duration
	telegraph.top_level = true # pinned to the world, not to the moving wolf
	add_child(telegraph)
	telegraph.global_position = global_position
	telegraph.line_to = to_position - global_position


## Client-visual: a FILLING danger ring (CastTelegraph) for a telegraphed boss
## slam — it fills + sweeps a clock-wedge over [param duration] so players read
## exactly when the hit lands, then vanishes as the impact takes over. World-
## pinned at the cast origin (the boss is rooted during the wind-up anyway).
func rp_cast_telegraph(center: Vector2, radius: float, duration: float) -> void:
	if multiplayer.is_server():
		return
	var tele: CastTelegraph = CastTelegraph.new()
	tele.radius = radius
	tele.duration = duration
	tele.top_level = true
	add_child(tele)
	tele.global_position = center


## Client-visual: the ground shockwave (SlamImpact) when a boss slam lands —
## expanding rings + debris radiating from the impact point. The "already
## happened" counterpart to the filling cast telegraph.
func rp_slam_impact(center: Vector2, radius: float) -> void:
	if multiplayer.is_server():
		return
	var impact: SlamImpact = SlamImpact.new()
	impact.max_radius = radius
	impact.color = Color(1.0, 0.5, 0.3, 0.9)
	impact.debris = 8
	impact.ring_count = 2
	impact.top_level = true
	add_child(impact)
	impact.global_position = center


func _process_animations() -> void:
	match enemy_state:
		EnemyState.RETURNING:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN
		EnemyState.IDLE:
			if anim != Character.Animations.IDLE:
				anim = Character.Animations.IDLE
		EnemyState.CHASE:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN
		EnemyState.ATTACK:
			# Attacking on the move reads as RUN; planted reads as IDLE.
			var attack_anim: Character.Animations = (
				Character.Animations.RUN if velocity.length_squared() > 1.0
				else Character.Animations.IDLE
			)
			if anim != attack_anim:
				anim = attack_anim
		EnemyState.LUNGE_WINDUP:
			if anim != Character.Animations.IDLE:
				anim = Character.Animations.IDLE
		EnemyState.LUNGING:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN


func _process_synchronization() -> void:
	container.mark_child_prop(_prop_id, _position_fid, position, true)
	container.mark_child_prop(_prop_id, _anim_fid, anim, true)
	container.mark_child_prop(_prop_id, _state_fid, enemy_state, true)
	container.mark_child_prop(_prop_id, _health_fid, stats_component.get_stat(Stat.HEALTH), true)
	container.mark_child_prop(_prop_id, _health_max_fid, stats_component.get_stat(Stat.HEALTH_MAX), true)


## Slow passive heal while idling. Without this, a mob that took a snipe
## from outside detection range would sit at low HP forever — even the
## new take_damage path that auto-engages doesn't help when the attacker
## stops shooting and walks off without ever entering the detection ring.
func _process_idle_regen() -> void:
	# Committed mobs (bosses) don't regen — their HP holds until the fight resumes.
	if _is_committed():
		return
	var hmax: float = stats_component.get_stat(Stat.HEALTH_MAX)
	var current_h: float = stats_component.get_stat(Stat.HEALTH)
	if current_h >= hmax:
		return
	var dt: float = get_physics_process_delta_time()
	var regen: float = hmax * IDLE_REGEN_RATE * dt
	stats_component.set_stat(Stat.HEALTH, minf(hmax, current_h + regen))


func _process_return() -> void:
	# Move toward spawn at the boosted return speed — outpaces typical
	# player movement so leashed mobs can't be re-kited.
	var direction: Vector2 = global_position.direction_to(spawn_position)
	velocity = direction * move_speed * RETURN_SPEED_MULTIPLIER
	move_and_slide()

	# Visible heal-on-the-walk: each physics tick credits a fraction of
	# (max HP × regen rate × dt). Reads as the bar filling while the mob
	# runs home, rather than a magic snap-to-full on arrival.
	var hmax: float = stats_component.get_stat(Stat.HEALTH_MAX)
	var current_h: float = stats_component.get_stat(Stat.HEALTH)
	if current_h < hmax:
		var dt: float = get_physics_process_delta_time()
		var regen: float = hmax * RETURN_REGEN_RATE * dt
		stats_component.set_stat(Stat.HEALTH, minf(hmax, current_h + regen))

	var distance_from_spawn: float = global_position.distance_to(spawn_position)
	if distance_from_spawn < 10: # minimum distance from spawn.
		# Snap remaining HP to full on arrival — handles the rounding edge
		# where the return walk ended a hair before full regen completed.
		if stats_component.get_stat(Stat.HEALTH) < hmax:
			stats_component.set_stat(Stat.HEALTH, hmax)
		enemy_state = EnemyState.IDLE


func _process_chase() -> void:
	if not _is_target_valid(targeted_player):
		_abandon_target()
		return
	if _target_escaped():
		stop_chase()
		return

	var direction: Vector2 = global_position.direction_to(targeted_player.global_position)
	velocity = direction * move_speed
	move_and_slide()

	var distance_from_spawn: float = global_position.distance_to(spawn_position)
	if distance_from_spawn > max_distance_from_spawn:
		stop_chase()
		return

	var distance_from_player: float = global_position.distance_to(targeted_player.global_position)
	if distance_from_player < distance_to_attack:
		enemy_state = EnemyState.ATTACK
		return

	# Telegraphed lunge: when the target sits in the pounce window (too far to
	# melee, close enough to pounce) and the cooldown is up, commit to a lunge.
	if lunge_range > 0.0 and Time.get_ticks_msec() >= _lunge_ready_at_ms:
		var lunge_min: float = maxf(distance_to_attack * 2.0, lunge_range * 0.4)
		if distance_from_player >= lunge_min and distance_from_player <= lunge_range:
			_begin_lunge()
			return


## Inside ATTACK state the mob keeps advancing until this fraction of its
## attack range, then plants — see _process_attack.
const ATTACK_ADVANCE_STOP_FRACTION: float = 0.65


func _process_attack() -> void:
	if not _is_target_valid(targeted_player):
		_abandon_target()
		return
	if _target_escaped():
		stop_chase()
		return

	# Same leash check the chase has — without this, a ranged player can
	# pull the mob to the edge of max_distance_from_spawn, then stand still
	# at attack range and farm forever because the mob never re-checks the
	# distance while in ATTACK state.
	var distance_from_spawn: float = global_position.distance_to(spawn_position)
	if distance_from_spawn > max_distance_from_spawn:
		stop_chase()
		return

	var distance_from_player: float = global_position.distance_to(targeted_player.global_position)
	if distance_from_player > distance_to_attack:
		enemy_state = EnemyState.CHASE
		return

	# Attack starts at distance_to_attack, but keep CLOSING IN while firing
	# until comfortably inside range — mobs shoot on the move like players do
	# instead of freezing at the range boundary. Melee mobs are already nearly
	# point-blank when this state starts, so only ranged feel changes.
	if distance_from_player > distance_to_attack * ATTACK_ADVANCE_STOP_FRACTION:
		velocity = global_position.direction_to(targeted_player.global_position) * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	# Auto-attack on cooldown.
	var now: int = Time.get_ticks_msec()
	if now >= _next_attack_ms:
		_next_attack_ms = now + int(attack_cooldown * 1000.0)
		if weapon != null:
			_perform_ranged_attack()
		else:
			_perform_melee_attack()


## Players this mob can strike right now: everyone the detection area is tracking,
## PLUS its active target. take_damage can set targeted_player WITHOUT a
## body_entered (a player who re-engaged after respawning inside our detection
## radius — so body_entered never re-fires — or a sniper from beyond it), and
## stop_chase erases the old target from possible_targets on a respawn-teleport.
## Without folding the target back in, the mob would telegraph but never connect.
func _strike_candidates() -> Array[Player]:
	var candidates: Array[Player] = possible_targets.duplicate()
	if targeted_player != null and not candidates.has(targeted_player):
		candidates.append(targeted_player)
	return candidates


## A swing: telegraph it on clients (red circle) and damage every living player within
## melee range (a small AoE), each mitigated by their armor in take_damage.
func _perform_melee_attack() -> void:
	container.queue_op(_prop_id, "rp_attack", [float(distance_to_attack)])
	var damage: float = stats_component.get_stat(Stat.AD)
	for candidate: Player in _strike_candidates():
		if _is_target_valid(candidate) \
				and _is_hostile_to(candidate) \
				and global_position.distance_to(candidate.global_position) <= distance_to_attack:
			candidate.take_damage(damage, self)


## Client-visual: flash the melee-range circle. Called via the container's rp_ op.
func rp_attack(radius: float) -> void:
	if multiplayer.is_server():
		return
	var telegraph: AttackTelegraph = AttackTelegraph.new()
	telegraph.radius = radius
	add_child(telegraph)


## Client-visual: a SpawnEffect summon burst centered on this mob — fired on spawn + respawn so an
## appearing mob has presence instead of popping in. A SEPARATE node (renders fine), not a tween on
## the mob's own sprite (which doesn't render — see docs/replicated_props_vfx.md).
func rp_spawn_effect() -> void:
	if multiplayer.is_server():
		return
	add_child(SpawnEffect.new())




## Replay one of this npc's rp_ visual methods on every client. Lets an external
## orchestrator (a BossController) drive the body's telegraphs without reaching
## into its private prop id. Server-side; no-op if not yet baked into a container.
func replicate_visual(method: StringName, args: Array) -> void:
	if container != null:
		container.queue_op(_prop_id, method, args)


## Scale this mob's combat stats for a harder run (dungeon Hard mode): multiply max
## health (and refill to it) + attack power. Generic — any spawner can call it after
## the mob's data has been applied.
func apply_difficulty(health_mult: float, damage_mult: float) -> void:
	var max_h: float = stats_component.get_stat(Stat.HEALTH_MAX) * health_mult
	stats_component.set_stat(Stat.HEALTH_MAX, max_h)
	stats_component.set_stat(Stat.HEALTH, max_h)
	stats_component.set_stat(Stat.AD, stats_component.get_stat(Stat.AD) * damage_mult)
	stats_component.set_stat(Stat.AP, stats_component.get_stat(Stat.AP) * damage_mult)


## Fires the equipped weapon's ability at the target. The server spawns the real
## (damaging) projectile; clients replay the shot via rp_shoot for the visual.
func _perform_ranged_attack() -> void:
	var mounted: Weapon = equipment_component.mounted_nodes.get(&"weapon")
	if mounted == null:
		return
	var direction: Vector2 = position.direction_to(targeted_player.global_position)
	mounted.auto_attack(direction)
	container.queue_op(_prop_id, "rp_shoot", [direction])


## Client-visual: replay the weapon shot so the projectile flies on every client.
func rp_shoot(direction: Vector2) -> void:
	if multiplayer.is_server():
		return
	var mounted: Weapon = equipment_component.mounted_nodes.get(&"weapon")
	if mounted:
		mounted.auto_attack(direction)


func _debug_client_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == &"health" or stat_name == &"health_max":
		print("[CLI NPC %s] sync %s → %.1f" % [enemy_type, stat_name, value])


## Spawn the detection-trigger Area2D as a child, sized to detection_radius
## (data-driven via EnemyTypeResource). Server-only; clients never see this.
func _build_detection_area() -> void:
	detection_area = Area2D.new()
	detection_area.name = "DetectionArea"
	# Default collision mask matches the existing scene's behaviour (all
	# layers, server filters body_entered down to Player). If you want to
	# narrow it for perf, set detection_area.collision_mask before adding.
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = float(detection_radius)
	shape.shape = circle
	detection_area.add_child(shape)
	add_child(detection_area)


# ---------------------------------------------------------------------------
# Debug visualisation
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not debug_draw_ranges:
		return
	# In editor we don't have enemy_data applied yet, so fall back to the
	# resource if one is assigned. Otherwise use whatever the local vars
	# currently hold (script default or @export set on the scene root).
	var leash: float = float(max_distance_from_spawn)
	var detect_r: float = float(detection_radius)
	if Engine.is_editor_hint() and enemy_data != null:
		leash = float(enemy_data.max_distance_from_spawn)
		detect_r = float(enemy_data.detection_radius)

	# Red (inner) = detection — "danger close", entering this ring trips
	# aggro. Yellow (outer) = leash — once the mob's chase crosses this
	# ring, it disengages and returns. Inner-red matches the player
	# intuition of "red = where the mob will jump on me".
	draw_circle(Vector2.ZERO, leash, Color(1, 0.9, 0.2, 0.08))
	draw_arc(Vector2.ZERO, leash, 0, TAU, 64, Color(1, 0.9, 0.2, 0.6), 1.0)
	draw_circle(Vector2.ZERO, detect_r, Color(1, 0.2, 0.2, 0.10))
	draw_arc(Vector2.ZERO, detect_r, 0, TAU, 48, Color(1, 0.2, 0.2, 0.6), 1.0)


## Equips the configured weapon (server + client) by setting the slot, which mounts it.
func _equip_weapon() -> void:
	if weapon == null or weapon.slot == null:
		return
	equipment_component.slots.set(weapon.slot.key, int(weapon.get_meta(&"id", 0)))


## Called by Character.take_damage when health hits zero (server-only).
func die(killer: Character) -> void:
	if DEBUG_NPC:
		printerr("[SRV NPC %s] die() killer=%s HP=%.1f state→DEAD respawn_in=%.1fs" % [
			enemy_type,
			String(killer.name) if killer else "null",
			stats_component.get_stat(Stat.HEALTH),
			respawn_delay
		])
	enemy_state = EnemyState.DEAD
	anim = Character.Animations.DEATH
	velocity = Vector2.ZERO
	targeted_player = null
	# Keep possible_targets so players still standing in the area are re-acquired on
	# respawn (body_entered won't re-fire for someone who never left).
	_respawn_at_ms = Time.get_ticks_msec() + int(respawn_delay * 1000.0)
	RewardService.distribute(self, _contributors, killer)
	died.emit(killer)


## Server-side override that:
## 1. Calls super to actually apply the damage.
## 2. Emits was_attacked so nearby pack-mates aggro the attacker.
## 3. Engages an IDLE mob that's been hit from outside detection range
##    (a far-away snipe wouldn't trigger CHASE through detection_area).
## 4. Pre/post logs gated on DEBUG_NPC for future bug triage.
func take_damage(amount: float, attacker: Character = null, damage_type: StringName = CombatHit.DAMAGE_PHYSICAL) -> void:
	# Ally protection: a guild guard ignores damage from its own guild's members.
	# Blocking here (before super) means no HP loss, no death, and no hit feedback
	# (numbers/flash/sound all hang off the HP-decrease push).
	if owner_guild_id > 0 and attacker is Player:
		var ap: Player = attacker
		if ap.player_resource != null and ap.player_resource.active_guild_id == owner_guild_id:
			return

	if not GameMode.is_world_server():
		super.take_damage(amount, attacker, damage_type)
		return

	# Participation: tally each player's damage BEFORE applying it, so a killing
	# blow is already counted when super → die() distributes the reward.
	if not is_dead and amount > 0.0 and attacker is Player and (attacker as Player).player_resource != null:
		var contributor_peer: int = int((attacker as Player).player_resource.current_peer_id)
		if contributor_peer > 0:
			_contributors[contributor_peer] = _contributors.get(contributor_peer, 0.0) + amount

	var was_alive: bool = not is_dead
	var pre_h: float = 0.0
	if DEBUG_NPC:
		pre_h = stats_component.get_stat(Stat.HEALTH)
		printerr("[SRV NPC %s] take_damage(%.1f) pre: HP=%.1f is_dead=%s state=%d attacker=%s" % [
			enemy_type, amount, pre_h, is_dead, enemy_state,
			String(attacker.name) if attacker else "null"
		])

	super.take_damage(amount, attacker, damage_type)

	if DEBUG_NPC:
		var post_h: float = stats_component.get_stat(Stat.HEALTH)
		if pre_h == post_h:
			printerr("[SRV NPC %s] take_damage(%.1f) NO-OP: HP unchanged (likely is_dead guard)" % [enemy_type, amount])
		else:
			printerr("[SRV NPC %s] take_damage(%.1f) post: HP=%.1f → %.1f is_dead=%s state=%d" % [
				enemy_type, amount, pre_h, post_h, is_dead, enemy_state
			])

	# Engagement triggers — only when the hit actually landed on a living
	# mob. Even if super killed us in the same call, was_alive captures the
	# pre-state so allies still get a "your buddy died fighting <attacker>"
	# notification and aggro the killer.
	if not was_alive or attacker == null:
		return
	# Pack-call: nearby HostileNpcs in detection_area pick this up.
	was_attacked.emit(attacker)
	# Self-engagement: a far-away snipe can't reach us through detection_area
	# (the attacker stays outside the ring) — so the take_damage path is
	# the only place we get to react. Don't re-target if we're already
	# chasing / attacking someone; don't break RETURNING / DEAD.
	if is_dead:
		return
	if enemy_state == EnemyState.RETURNING or enemy_state == EnemyState.DEAD:
		return
	if targeted_player != null:
		return
	if attacker is Player and not (attacker as Player).is_dead and _is_hostile_to(attacker as Player):
		targeted_player = attacker as Player
		enemy_state = EnemyState.CHASE


## Drops the current target and heads home (used when the target dies or is lost).
## A committed mob (enemy_data.leashes == false: bosses + world bosses) never leashes
## home and never regenerates — it holds its current HP and just idles in place when it
## loses its target, re-aggroing via _find_targets the moment a player is back in reach.
## You can't reset a boss by dying or running off; with nobody around it simply idles.
## (Distance-leashing mobs keep the normal march-home + regen.)
func _is_committed() -> bool:
	return enemy_data != null and not enemy_data.leashes


func _abandon_target() -> void:
	targeted_player = null
	enemy_state = EnemyState.IDLE if _is_committed() else EnemyState.RETURNING


func _process_death() -> void:
	if Time.get_ticks_msec() < _respawn_at_ms:
		return
	# Single-life mobs — guild defenders AND any enemy_data.respawns == false
	# (dungeon mobs, one-off bosses) — despawn instead of respawning. All are
	# dynamic props.
	if owner_guild_id > 0 or not respawns:
		container.despawn_dynamic(_prop_id)
		return
	if DEBUG_NPC:
		printerr("[SRV NPC %s] _process_death respawn START: HP=%.1f HP_MAX=%.1f is_dead=%s state=%d" % [
			enemy_type, stats_component.get_stat(Stat.HEALTH), stats_component.get_stat(Stat.HEALTH_MAX), is_dead, enemy_state
		])
	# Respawn at the original spot, full health, idle.
	global_position = spawn_position
	# Defensive: re-derive HEALTH_MAX from the archetype if it got into a
	# bad (zero) state somewhere. Without this, a HEALTH_MAX=0 leaves the
	# NPC at HEALTH=0 after respawn — visible as the "zombie NPC" bug where
	# the bar reads empty client-side and any hit immediately re-kills the
	# mob in take_damage. Cheap and idempotent in the healthy path.
	var hmax: float = stats_component.get_stat(Stat.HEALTH_MAX)
	if hmax <= 0.0:
		# common/ can't reference ServerLog (source/server/* is stripped from
		# the client export filter). printerr lands in stderr → journalctl
		# picks it up on the live box, which is where you'd look anyway.
		printerr("NPC %s respawned with HEALTH_MAX=%f, restoring to archetype max_health=%d" % [enemy_type, hmax, max_health])
		hmax = float(max_health)
		stats_component.set_stat(Stat.HEALTH_MAX, hmax)
	stats_component.set_stat(Stat.HEALTH, hmax)

	# Diagnostic for "zombie NPC: bar empty, can't damage" — you confirmed
	# HEALTH_MAX is intact and only HEALTH is 0 on the bar. So the question
	# is whether the server wrote HEALTH=hmax here and got eaten somewhere,
	# or whether write itself didn't take. Print the post-write value so
	# the next repro shows which side of the boundary the issue is on.
	var post_h: float = stats_component.get_stat(Stat.HEALTH)
	if post_h <= 0.0:
		printerr("NPC %s respawn: HEALTH wrote=%f got=%f HEALTH_MAX=%f — zombie forming" % [enemy_type, hmax, post_h, stats_component.get_stat(Stat.HEALTH_MAX)])
	is_dead = false
	enemy_state = EnemyState.IDLE
	_contributors.clear() # fresh life — past damage no longer counts for rewards
	# Push the respawn position NOW (the freeze below skips the normal per-frame sync) so the spawn
	# FX lands on the mob at its spawn point, not at wherever it happened to die.
	_process_synchronization()
	# Summon burst + brief hold so a respawned mob phases in instead of blinking + instantly chasing.
	action_root_until_ms = Time.get_ticks_msec() + int(SPAWN_FREEZE_S * 1000.0)
	replicate_visual(&"rp_spawn_effect", [])
	if DEBUG_NPC:
		printerr("[SRV NPC %s] _process_death respawn END: HP=%.1f is_dead=%s state=%d" % [
			enemy_type, stats_component.get_stat(Stat.HEALTH), is_dead, enemy_state
		])


## If npc is engaged (chasing or attacking), stops and starts returning to
## the spawn position. Accepts ATTACK too so the new leash check in
## _process_attack can route through here without re-implementing the
## possible_targets / target cleanup.
func stop_chase() -> void:
	if enemy_state != EnemyState.CHASE and enemy_state != EnemyState.ATTACK: return
	enemy_state = EnemyState.IDLE if _is_committed() else EnemyState.RETURNING
	possible_targets.erase(targeted_player)
	targeted_player = null
