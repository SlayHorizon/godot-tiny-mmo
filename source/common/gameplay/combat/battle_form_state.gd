class_name BattleFormState
extends Node
## Server-side Battle Form runtime: raises the caster's MAX + CURRENT health by
## [member bonus_hp] and scales their HURTBOX (the bigger body is genuinely easier to
## hit — the Archon tradeoff for the HP wall) for [member duration], then reverts: drops
## the max back, CLAMPS current HP to it, unscales the hurtbox, frees. The client-side
## sprite grow + rune VFX ride a separate battleform.start push (InstanceClient).
##
## Manual (not BuffService) because we grant CURRENT hp + must clamp it on revert — a plain
## stat buff would raise max but leave you below it, and wouldn't pull HP back down after.

var caster: Character
var bonus_hp: float = 180.0
var scale_factor: float = 1.6
var duration: float = 8.0


func _ready() -> void:
	if not is_instance_valid(caster) or caster.stats_component == null:
		queue_free()
		return
	caster.stats_component.modify_stat(Stat.HEALTH_MAX, bonus_hp)
	caster.stats_component.modify_stat(Stat.HEALTH, bonus_hp)
	# Scale the whole root so the HURTBOX grows with the body (the bigger-target tradeoff).
	# Server has no camera child, so scaling the root here is safe; the client compensates
	# its own camera (InstanceClient._on_battleform). Scale isn't synced, so no double-scale.
	caster.scale *= scale_factor
	await get_tree().create_timer(duration).timeout
	_revert()


func _revert() -> void:
	if is_instance_valid(caster) and caster.stats_component != null:
		caster.stats_component.modify_stat(Stat.HEALTH_MAX, -bonus_hp)
		var new_max: float = caster.stats_component.get_stat(Stat.HEALTH_MAX)
		var cur: float = caster.stats_component.get_stat(Stat.HEALTH)
		if cur > new_max:
			caster.stats_component.set_stat(Stat.HEALTH, new_max)  # lose the temp buffer
		caster.scale /= scale_factor
	queue_free()
