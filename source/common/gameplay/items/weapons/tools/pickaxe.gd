class_name Pickaxe
extends Weapon
## Visible-in-hand pickaxe. No combat abilities — it's a tool. play_pick_swing
## is called by MineableNode.on_click so the player gets a "swing" feedback
## animation regardless of whether the gather succeeds (failed gathers still
## feel like an attempt that missed instead of a dead click).


## Total pick-swing duration in seconds. Tween animates rotation + a tiny
## y-bob; the WeaponSprite is offset by the Weapon scene so this rotation
## reads as a swing from over-the-shoulder down to ore-level.
const SWING_DURATION_S: float = 0.45
## Peak rotation in radians during the swing apex.
const SWING_PEAK_RAD: float = 1.0

var _swing_tween: Tween


func play_pick_swing() -> void:
	if not GameMode.is_client() or weapon_sprite == null:
		return
	if _swing_tween != null and _swing_tween.is_running():
		_swing_tween.kill()
	# Reset to neutral before swinging, so back-to-back clicks always start
	# from the right pose instead of compounding rotation.
	weapon_sprite.rotation = 0.0
	_swing_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	_swing_tween.tween_property(weapon_sprite, ^"rotation", -SWING_PEAK_RAD, SWING_DURATION_S * 0.35)\
		.set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(weapon_sprite, ^"rotation", SWING_PEAK_RAD * 0.4, SWING_DURATION_S * 0.35)\
		.set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(weapon_sprite, ^"rotation", 0.0, SWING_DURATION_S * 0.30)\
		.set_ease(Tween.EASE_OUT)
