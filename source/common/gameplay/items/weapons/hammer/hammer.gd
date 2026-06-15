extends Weapon
## War Hammer: the base Weapon plus a punchy, code-driven slam (wind-up →
## anticipation hold → violent snap → recoil) on the weapon, plus an on-impact
## ground shockwave (SlamImpact) + debris + screen shake. All the JUICE scales
## PER ABILITY — the basic tap is modest, Earthshatter is a screen-shaking,
## rock-spitting showpiece — by reading the performed AbilityResource's
## impact_shake / impact_reach / impact_particles. Code-driven because juice is
## procedural; a keyframed body animation can layer on top later.

## Slam timing — slow wind-up, a beat of anticipation, then a FAST smash, so it
## reads as heavy. Smash drives PAST 90° so the head clearly hits the ground.
const RAISE_S: float = 0.14   ## raise the hammer high overhead
const HOLD_S: float = 0.05    ## hang at the top (anticipation)
const SMASH_S: float = 0.22   ## the DESCENT — long enough for the eye to track
const GROUND_HOLD_S: float = 0.1  ## stay planted in the crater (weight) before lifting
const SETTLE_S: float = 0.26  ## recoil back to rest, overshooting
const RAISE_ANGLE: float = -120.0
const SMASH_ANGLE: float = 95.0   ## past vertical — reads as a ground slam
const SMASH_SCALE: float = 1.6    ## peak head size at the moment of contact

## The slam's hitbox is a CENTERED circle on the wielder, so the ring is drawn
## centered too — it now MATCHES the damage zone (no forward offset). The head
## still visually comes down via the rotation tween; the shockwave radiates from
## your feet, which is honest for a centered AoE.

var _slam_tween: Tween
## The ability + aim of the swing in flight, captured for the impact callback.
var _slam_ability: AbilityResource
var _slam_dir: Vector2 = Vector2.RIGHT


func perform_action(action_index: int, direction: Vector2, released: bool = false) -> void:
	super.perform_action(action_index, direction, released)
	if action_index < 0 or action_index >= abilities.size():
		return
	var ability: AbilityResource = abilities[action_index]
	# Only the melee SLAMS get the punchy slam swing. A channeled special (the
	# healing aura) uses its own stance pose — it must NOT trigger a swing.
	if ability is not MeleeSwingAbility:
		return
	_slam_ability = ability
	_slam_dir = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	# Plant the wielder for the swing (commit). CLIENT-ONLY — ClientState is a
	# client autoload (freed on the server), and perform_action runs on both.
	if GameMode.is_client() and character == ClientState.local_player and ClientState.local_player != null:
		ClientState.local_player.freeze_movement(_slam_ability.root_s)
	_play_slam_visual()


func _play_slam_visual() -> void:
	# Visual only — the headless server skips it. Runs for the wielder AND for
	# everyone else via the action.perform broadcast replay. Tweens the weapon
	# ROOT (self) so the hand swings with the hammer.
	if not GameMode.is_client():
		return
	if _slam_tween != null and _slam_tween.is_running():
		_slam_tween.kill()
	rotation_degrees = 0.0
	if weapon_sprite != null:
		weapon_sprite.scale = Vector2.ONE
	# A telegraphed ability (Earthshatter) stretches the wind-up to fill its
	# cast time, so the smash + impact land exactly when the delayed damage and
	# the telegraph resolve. Instant abilities keep the snappy default timing.
	var raise_t: float = RAISE_S
	var hold_t: float = HOLD_S
	var cast: float = _slam_ability.cast_time_s if _slam_ability != null else 0.0
	if cast > 0.0:
		var windup: float = maxf(0.1, cast - SMASH_S)
		raise_t = windup * 0.85
		hold_t = windup * 0.15
	# Big telegraphed slams stay planted a touch longer (more weight).
	var ground_hold: float = GROUND_HOLD_S + (0.1 if cast > 0.0 else 0.0)
	var has_sprite: bool = weapon_sprite != null

	_slam_tween = create_tween()
	# Wind up high and slow...
	_slam_tween.tween_property(self, ^"rotation_degrees", RAISE_ANGLE, raise_t)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# ...hang a beat (the anticipation that sells the weight)...
	_slam_tween.tween_interval(hold_t)
	# ...then drive down past vertical. QUAD (not EXPO) ease-in so the descent is
	# VISIBLE the whole way — it accelerates into the ground rather than
	# teleporting there on the last frame. The head SWELLS in parallel, peaking on
	# contact, so the size punch reads DURING the fall, not after it.
	_slam_tween.tween_property(self, ^"rotation_degrees", SMASH_ANGLE, SMASH_S)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if has_sprite:
		_slam_tween.parallel().tween_property(weapon_sprite, ^"scale", Vector2(SMASH_SCALE, SMASH_SCALE), SMASH_S)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Impact: shockwave + debris + shake, on the smash's last frame.
	_slam_tween.tween_callback(_on_slam_impact)
	# Stay planted in the crater a beat — a heavy head doesn't bounce off, it
	# sticks (head stays fat the whole time it's embedded).
	_slam_tween.tween_interval(ground_hold)
	# ...then lift back to rest with a slight overshoot at the top (arm relaxing),
	# the head shrinking back to normal in parallel as it rises.
	_slam_tween.tween_property(self, ^"rotation_degrees", 0.0, SETTLE_S)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if has_sprite:
		_slam_tween.parallel().tween_property(weapon_sprite, ^"scale", Vector2.ONE, SETTLE_S)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_slam_impact() -> void:
	# Per-ability juice (basic tap is modest, Earthshatter is huge). Defaults
	# keep a bare slam feeling decent even if an ability declares nothing.
	var shake: float = _slam_ability.impact_shake if _slam_ability != null else 0.3
	var reach: float = _slam_ability.impact_reach if _slam_ability != null else 32.0
	var debris: int = _slam_ability.impact_particles if _slam_ability != null else 4
	var color: Color = _slam_ability.impact_color if _slam_ability != null else Color(1.0, 0.92, 0.55, 0.9)
	var rings: int = _slam_ability.impact_rings if _slam_ability != null else 1

	# (The head scale-punch runs as a parallel tween synced to the descent — see
	# _play_slam_visual — so the swell peaks ON contact, not after it.)

	# Ground shockwave + debris, CENTERED on the wielder to match the centered
	# AoE hitbox. Ring radius = the ability's hitbox so it reads as real reach.
	if reach > 0.0 and character != null and character.get_parent() != null:
		var impact: SlamImpact = SlamImpact.new()
		impact.max_radius = reach
		impact.debris = debris
		impact.color = color
		impact.ring_count = rings
		character.get_parent().add_child(impact)
		impact.global_position = character.global_position

	# Screen shake — only for the player whose hammer this is.
	if shake > 0.0 and character == ClientState.local_player and ClientState.local_player != null:
		ClientState.local_player.shake_camera(shake)


# --- Channel stance (healing aura): the hammer plants, swells, and floats ---
var _pose_tween: Tween
var _bob_tween: Tween
var _sprite_rest_pos: Vector2
var _posing: bool = false


## Plant the hammer in a held stance while a channel runs: it swells and floats
## with a gentle bob, the hand frozen (LocalPlayer stops aiming during a channel),
## so it reads as a committed pose rather than a swing. Restores on exit.
func set_channeling_pose(active: bool) -> void:
	if not GameMode.is_client() or weapon_sprite == null or active == _posing:
		return
	_posing = active
	if _pose_tween != null and _pose_tween.is_running():
		_pose_tween.kill()
	if _bob_tween != null and _bob_tween.is_running():
		_bob_tween.kill()
	if active:
		# Drop any in-flight slam so the pose owns the weapon transform cleanly.
		if _slam_tween != null and _slam_tween.is_running():
			_slam_tween.kill()
		rotation_degrees = 0.0
		weapon_sprite.scale = Vector2.ONE
		# Sprite position is stable (only apply_skin sets it; the slam never moves
		# it), so capturing it here is a safe rest point to bob around + restore to.
		_sprite_rest_pos = weapon_sprite.position
		_pose_tween = create_tween()
		_pose_tween.tween_property(weapon_sprite, ^"scale", Vector2(1.3, 1.3), 0.18)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_bob_tween = create_tween().set_loops()
		_bob_tween.tween_property(weapon_sprite, ^"position:y", _sprite_rest_pos.y - 5.0, 0.7)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_bob_tween.tween_property(weapon_sprite, ^"position:y", _sprite_rest_pos.y - 1.0, 0.7)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_pose_tween = create_tween()
		_pose_tween.set_parallel()
		_pose_tween.tween_property(weapon_sprite, ^"scale", Vector2.ONE, 0.18)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_pose_tween.tween_property(weapon_sprite, ^"position", _sprite_rest_pos, 0.18)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
