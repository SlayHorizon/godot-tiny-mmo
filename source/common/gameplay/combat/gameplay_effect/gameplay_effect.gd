class_name GameplayEffect
extends Resource


@export var name_id: StringName
@export var is_debuff: bool = true
@export_flags("Magic","Physical","Poison","Curse","CC","Buff") var dispel_mask: int = 0
@export var tags: PackedStringArray = []

@export var duration: float = 0.0
@export var period: float = 0.0
@export var first_tick_delay: float = 0.0
@export var stacks_max: int = 1


var _owner_id: int = randi()
var _expires_at: float = -1.0
var _next_tick_at: float = -1.0
var _stacks: int = 1
var _source: AbilitySystemComponent = null


func on_added(_asc: AbilitySystemComponent) -> void:
	pass


func on_removed(asc: AbilitySystemComponent) -> void:
	asc.unsubscribe_all(_owner_id)


func on_tick(_asc: AbilitySystemComponent) -> void:
	pass


func _sub(asc: AbilitySystemComponent, event: StringName, tag: StringName, prio: int, method: StringName) -> void:
	asc.subscribe(event, tag, prio, Callable(self, method), _owner_id)
