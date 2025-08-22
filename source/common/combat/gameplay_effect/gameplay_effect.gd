# GameplayEffect.gd
class_name GameplayEffect
extends Resource

@export var name_id: StringName
# GameplayEffect.gd (ajoute ces champs)
@export var is_debuff: bool = true
@export_flags("Magic","Physical","Poison","Curse","CC","Buff") var dispel_mask: int = 0
@export var tags: PackedStringArray = []   # utile pour filtrer par tag ("GrievousWounds", etc.)

var _owner_id: int = randi()

func on_added(asc: AbilitySystemComponent) -> void:
	# override et subscribe ici
	pass

func on_removed(asc: AbilitySystemComponent) -> void:
	asc.unsubscribe_all(_owner_id)

func _sub(asc: AbilitySystemComponent, event: StringName, tag: StringName, prio: int, method: StringName) -> void:
	asc.subscribe(event, tag, prio, Callable(self, method), _owner_id)
