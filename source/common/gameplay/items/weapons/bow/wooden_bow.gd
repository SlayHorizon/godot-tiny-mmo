extends Weapon
## Bow VISUALS only — draw frames + charge/idle animation states. All gameplay
## (charge timing, damage ratios, projectile speed, multishot, mana cost) lives
## in the ChargeAbility .tres files on the scene's abilities array:
##   abilities[0] = primary charged shot, abilities[1] = multishot.
## Input, charge state, cooldowns and firing are the base Weapon + ChargeAbility
## pipeline — this script just reacts to "is my ability charging?" after each
## action to keep the bow's sprite honest.

## bone.png sprite-sheet regions for the bow's 3 charge frames. Frame 0 =
## relaxed bow at rest, frame 1 = half-draw, frame 2 = full draw. All 16x32.
const BOW_CHARGE_FRAMES: Array[Rect2] = [
	Rect2(48, 48, 16, 32),
	Rect2(64, 48, 16, 32),
	Rect2(80, 48, 16, 32),
]

## Active tween driving the WeaponSprite region swap. Killed on each new phase
## so charge → release → re-charge doesn't leave a stale frame.
var _charge_tween: Tween


func perform_action(action_index: int, direction: Vector2, released: bool = false) -> void:
	super.perform_action(action_index, direction, released)
	if not GameMode.is_client():
		return
	if action_index < 0 or action_index >= abilities.size():
		return
	var ability: AbilityResource = abilities[action_index]
	if ability is not ChargeAbility:
		return
	if (ability as ChargeAbility).charging:
		character.weapon_state_machine.travel(&"weapon_charge")
		_play_charge_frames((ability as ChargeAbility).charge_time_s)
	else:
		character.weapon_state_machine.travel(&"weapon_idle")
		_reset_charge_frame()


## Steps the WeaponSprite through its 3 charge frames: frame 0 → 1 at half the
## charge time, 1 → 2 at full charge. Snap transitions (no Rect2 lerp — that
## produces nonsense intermediate regions).
func _play_charge_frames(charge_time_s: float) -> void:
	if weapon_sprite == null:
		return
	if _charge_tween != null and _charge_tween.is_running():
		_charge_tween.kill()
	weapon_sprite.region_rect = BOW_CHARGE_FRAMES[0]
	_charge_tween = create_tween()
	_charge_tween.tween_interval(charge_time_s * 0.5)
	_charge_tween.tween_callback(_set_charge_frame.bind(1))
	_charge_tween.tween_interval(charge_time_s * 0.5)
	_charge_tween.tween_callback(_set_charge_frame.bind(2))


func _set_charge_frame(index: int) -> void:
	if weapon_sprite == null or index < 0 or index >= BOW_CHARGE_FRAMES.size():
		return
	weapon_sprite.region_rect = BOW_CHARGE_FRAMES[index]


func _reset_charge_frame() -> void:
	if _charge_tween != null and _charge_tween.is_running():
		_charge_tween.kill()
	if weapon_sprite != null:
		weapon_sprite.region_rect = BOW_CHARGE_FRAMES[0]
