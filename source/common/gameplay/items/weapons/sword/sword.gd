extends Weapon
## Thin holder for sword-flavoured tuning. Actual swing behaviour lives in
## the assigned MeleeSwingAbility (combat/ability/ability_collection/
## melee_swing/). Future swords (rapier, claymore) inherit nothing extra —
## they just point at a different MeleeSwingAbility.tres with different
## base_damage / spawn_offset / animation values.


func _ready() -> void:
	super._ready()
	if not GameMode.is_client():
		return
	# Load the sword animation library onto the character's AnimationPlayer
	# so swing_animation paths like "weapon/sword.swing" resolve. Idempotent
	# across multiple sword instances on the same character (shouldn't
	# happen, but cheap to guard).
	if not character.animation_player.has_animation_library(&"weapon"):
		character.animation_player.add_animation_library(
			&"weapon",
			animation_libraries[&"weapon"]
		)
