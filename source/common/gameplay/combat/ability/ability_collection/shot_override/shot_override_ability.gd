class_name ShotOverrideAbility
extends AbilityResource
## The bow's SHOT OVERRIDE: pressing this ability fires nothing — it ARMS your next
## charged draw (Multishot fans it, Deadeye makes it a piercing sniper round, Frozen
## Arrow turns it into the ice ultimate). One verb (the draw), many adjectives.
##
## Born from a live abuse: when every bow ability was its own instant attack, testers
## fired the basic + an ability back-to-back for two full attacks a second. An override
## can't add an attack by construction — it only re-flavors the one you were drawing.
## Bonus: the armed shot still scales with DRAW time, so a panic-tap Multishot is weak
## and a full-draw one is the real volley.
##
## Rules (docs/bow.md): one override armed at a time (re-arm replaces), cooldown+mana
## stamp on press, ~EXPIRY_S grace then it fizzles. Armed state lives in
## Character.armed_shot, set identically on every peer by the action echo; the consume
## happens in ChargeAbility.release_ability on every peer too — deterministic, no sync.

const EXPIRY_S: float = 6.0

## Arrows in the released shot (3 = Multishot fan; 1 keeps a single arrow — Deadeye).
@export var projectile_count: int = 1
## Half-cone in degrees when projectile_count > 1.
@export var spread_deg: float = 18.0
## Per-arrow damage factor (fans use < 1.0 so a volley isn't a burst nuke).
@export var damage_factor: float = 1.0
## Extra damage multiplier on the whole shot (Deadeye's punch). 1.0 = none.
@export var damage_mult: float = 1.0
## Projectile speed multiplier (a sniper round flies faster). 1.0 = none.
@export var speed_mult: float = 1.0
## Targets pierced before stopping (0 = none; 99 ≈ everything — Deadeye II).
@export var pierce_count: int = 0
## STUN the first target hit for this long (the Pinning Arrow ult — the game's first
## hard CC; immunity-gated server-side). 0 = none.
@export var stun_s: float = 0.0
## Shockwave around the impact: radius + slow (the pin's area denial). 0 = none.
@export var impact_radius: float = 0.0
@export var impact_slow: float = 0.0
@export var impact_slow_s: float = 0.0
## Visual scale on the arrow itself (2+ = the giant ult arrow). 1 = normal.
@export var shot_scale: float = 1.0
## Armed-glow tint on the hand while loaded (also how enemies read what's coming).
@export var glow_color: Color = Color(1.0, 0.85, 0.4)

const GLOW_VFX: SpriteFrames = preload("res://source/common/gameplay/combat/vfx/lash_burst.tres")
const GLOW_NODE: StringName = &"ArmedShotGlow"


## Arming while ALREADY armed is refused — the loaded shot is a commitment (owner rule:
## while armed, no other abilities either; that half lives in the weapon/server gates).
## Cooldown + mana are charged when the SHOT FIRES (the consume in ChargeAbility), not
## here — arming is intent, the draw is the cast.
func can_use(user: Entity = null) -> bool:
	if user is Character and (user as Character).has_armed_shot():
		return false
	return super.can_use(user)


func use_ability(user: Entity, _direction: Vector2) -> void:
	if user is not Character:
		return
	var character: Character = user as Character
	# Arm (replacing anything already loaded). Runs on EVERY peer via the action echo,
	# so server damage and all clients' visuals agree on what's loaded.
	character.armed_shot = {
		"name": name,
		"count": projectile_count,
		"spread": spread_deg,
		"factor": damage_factor,
		"mult": damage_mult,
		"speed": speed_mult,
		"pierce": pierce_count,
		"stun": stun_s,
		"exp_r": impact_radius,
		"exp_slow": impact_slow,
		"exp_slow_s": impact_slow_s,
		"scale": shot_scale,
		"at": Time.get_ticks_msec(),
	}
	if not GameMode.is_client():
		return
	# The armed glow: a soft loop on the hand until consumed or expired.
	if character.right_hand_spot == null:
		return
	var old: Node = character.right_hand_spot.get_node_or_null(NodePath(GLOW_NODE))
	if old != null:
		# Rename BEFORE the deferred free — otherwise the new glow's name collides,
		# gets auto-renamed, and the consume can never find it (the stale-glow bug).
		old.name = &"ArmedShotGlowDying"
		old.queue_free()
	var fx: SpriteEffect = SpriteEffect.spawn(character.right_hand_spot, GLOW_VFX, {
		"loop": true,
		"duration": EXPIRY_S,
		"scale": Vector2(0.22, 0.22),
		"modulate": glow_color,
		"z_index": 1,
	})
	if fx != null:
		fx.name = GLOW_NODE


## Consume/clear helper used by ChargeAbility on release (every peer) and by expiry.
static func clear_armed(character: Character) -> void:
	character.armed_shot = {}
	if not GameMode.is_client() or character.right_hand_spot == null:
		return
	var fx: Node = character.right_hand_spot.get_node_or_null(NodePath(GLOW_NODE))
	if fx != null:
		fx.queue_free()


## Read the armed override if still fresh; expired ones fizzle (and clean up).
static func take_armed(character: Character) -> Dictionary:
	if character.armed_shot.is_empty():
		return {}
	var armed: Dictionary = character.armed_shot
	clear_armed(character)
	if Time.get_ticks_msec() - int(armed.get("at", 0)) > int(EXPIRY_S * 1000.0):
		return {} # fizzled — armed too long ago
	return armed


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if projectile_count > 1:
		lines.append("%d arrows, %d%% damage each" % [projectile_count, int(round(damage_factor * 100.0))])
	if damage_mult > 1.0:
		lines.append("+%d%% damage" % int(round((damage_mult - 1.0) * 100.0)))
	if pierce_count > 0:
		lines.append("pierces everything" if pierce_count >= 99 else "pierces %d targets" % pierce_count)
	if speed_mult > 1.0:
		lines.append("+%d%% arrow speed" % int(round((speed_mult - 1.0) * 100.0)))
	if stun_s > 0.0:
		lines.append("pins the target for %ss" % fmt_num(stun_s))
	if impact_slow > 0.0:
		lines.append("-%s move speed around the impact" % fmt_num(impact_slow))
	lines.append("arms your next draw")
	return lines
