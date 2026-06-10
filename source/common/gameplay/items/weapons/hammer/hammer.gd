extends Weapon
## War Hammer: the base Weapon plus a simple code-driven slam visual (raise →
## smash → settle) on the weapon sprite. Code tween instead of an authored
## AnimationLibrary so the hammer reads as heavy without touching the character
## animation graph; replace with a real keyframed swing when weapon animations
## get an authoring pass.

## Wind-up / impact / settle timing, tuned to read "heavy" against the 2.8s
## slam cooldown (total ≈ 0.45s, well inside it).
const RAISE_S: float = 0.18
const SMASH_S: float = 0.07
const SETTLE_S: float = 0.20

var _slam_tween: Tween


func perform_action(action_index: int, direction: Vector2, released: bool = false) -> void:
	super.perform_action(action_index, direction, released)
	_play_slam_visual()


func _play_slam_visual() -> void:
	# Visual only — the headless server skips it. Runs for the wielder AND for
	# everyone else via the action.perform broadcast replay. Tweens the weapon
	# ROOT (self) so the hand swings together with the hammer, not the sprite
	# alone with the hand floating in place.
	if not GameMode.is_client():
		return
	if _slam_tween != null and _slam_tween.is_running():
		_slam_tween.kill()
	rotation_degrees = 0.0
	_slam_tween = create_tween()
	# Raise back...
	_slam_tween.tween_property(self, ^"rotation_degrees", -75.0, RAISE_S)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# ...smash through past neutral...
	_slam_tween.tween_property(self, ^"rotation_degrees", 35.0, SMASH_S)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# ...and settle back to rest.
	_slam_tween.tween_property(self, ^"rotation_degrees", 0.0, SETTLE_S)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
