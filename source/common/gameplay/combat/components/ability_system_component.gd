class_name AbilitySystemComponent
extends Node


@export var synchronizer: StateSynchronizer


var modifiers: Array[StatModifier]
var attributes: Attributes = Attributes.new()

class Attributes:
	var attributes: Dictionary[StringName, float]
	var watchers: Dictionary[StringName, Array]
	
	
	func _set(property: StringName, value: Variant) -> bool:
		if not typeof(value) == TYPE_FLOAT:
			return false
		for watcher: Callable in watchers.get(property, []):
				watcher.call(value)
		attributes.set(property, value)
		return true


	func _get(property: StringName) -> Variant:
		return attributes.get(property, 0.0)


	func connect_watcher(property: StringName, to_connect: Callable) -> void:
		if watchers.has(property):
			watchers[property].append(to_connect)
		else:
			watchers[property] = [to_connect]
		to_connect.call(attributes.get(property, 0.0))

static func attribute_path(attribute_name: StringName) -> String:
	return "AbilitySystemComponent:attributes:%s" % attribute_name


func _ready() -> void:
	pass


func ensure_attribute(attribute_name: StringName, value: float) -> void:
	attributes[attribute_name] = value
	PathRegistry.register_field(attribute_path(attribute_name), Wire.Type.F32)
	synchronizer.set_by_path(attribute_path(attribute_name), value)


func get_attribute_value(attribute_name: StringName) -> float:
	return attributes.get(attribute_name)


func set_attribute_value(attribute_name: StringName, value: float, source: StringName = &"") -> void:
	ensure_attribute(attribute_name, value)
	mark_attribute(attribute_name, value)


func mark_attribute(
	attribute_name: StringName,
	attribute_value: float,
	only_if_changed: bool = true
) -> void:
	synchronizer.mark_dirty_by_path(
		attribute_path(attribute_name),
		attribute_value,
		only_if_changed
	)


# Gameplay
# Dead simple logic for now
func apply_damage(damage: float) -> void:
	set_attribute_value(
		Stat.HEALTH,
		get_attribute_value(Stat.HEALTH) - damage
	)


func add_modifier(modifier: StatModifier) -> void:
	modifiers.append(modifier)
	#attributes[modifier.stat_id] += modifier.value

func remove_modifier(modifier: StatModifier) -> void:
	modifiers.erase(modifier)


func recalc_modifiers() -> void:
	pass
