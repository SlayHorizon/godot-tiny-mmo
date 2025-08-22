# ThornmailEffect.gd
class_name ThornmailEffect
extends GameplayEffect

@export var reflect_ratio: float = 0.25
@export var grievous_duration: float = 2.0

func on_added(asc: AbilitySystemComponent) -> void:
	# écoute toute forme de dégâts (Damage.*), priorité basse pour passer après mitigation
	_sub(asc, &"OnSpecPostApply", &"Damage", 50, &"_on_post")

func _on_post(ev: GameplayEvent, self_asc: AbilitySystemComponent) -> void:
	if ev.canceled or ev.amount <= 0.0:
		return
	# ignore boucles de réflexion
	if ev.spec.tags.has("Reflect"):
		return
	var src := ev.source
	if src == null:
		return

	# 1) Anti-heal (Grievous Wounds) sur la source
	# LAter
	#var griev := GrievousWoundsEffect.new()
	#griev.name_id = &"Grievous"
	#griev.is_debuff = true
	#griev.dispel_mask = AbilitySystemComponent.DISPEL_MAGIC
	#griev.duration = grievous_duration
	#src.add_effect(griev)

	# 2) Réflexion partielle
	var back := EffectSpec.damage(
		self_asc.get_parent().name.to_int(),
		ev.amount * reflect_ratio,
		["Damage.Magic","Reflect"]  # tag Reflect pour stopper cascades
	)
	src.apply_spec_server(back, self_asc)
