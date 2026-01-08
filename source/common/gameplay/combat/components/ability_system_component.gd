class_name AbilitySystemComponent
extends Node


signal entity_died(entity: Character, killer: Character)


@export var synchronizer: StateSynchronizer


var modifiers: Array[StatModifier]
var last_damage_source: Character = null
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


## Wrapper method for backward compatibility with Character code
## Forwards to attributes.connect_watcher()
func connect_watcher(property: StringName, to_connect: Callable) -> void:
	attributes.connect_watcher(property, to_connect)


func ensure_attribute(attribute_name: StringName, value: float) -> void:
	# Use set() to trigger _set() and watchers (for both server and client)
	attributes.set(attribute_name, value)
	PathRegistry.register_field(attribute_path(attribute_name), Wire.Type.F32)
	synchronizer.set_by_path(attribute_path(attribute_name), value)


func get_attribute_value(attribute_name: StringName) -> float:
	return attributes.get(attribute_name)


func set_attribute_value(attribute_name: StringName, value: float, source: StringName = &"") -> void:
	ensure_attribute(attribute_name, value)
	mark_attribute(attribute_name, value)


func _get_replicated_props_container() -> ReplicatedPropsContainer:
	# Check if parent is in a ReplicatedPropsContainer (for NPCs)
	var parent: Node = get_parent()
	if not parent:
		return null
	
	# Check if parent's parent is a ReplicatedPropsContainer
	var grandparent: Node = parent.get_parent()
	if grandparent is ReplicatedPropsContainer:
		return grandparent as ReplicatedPropsContainer
	
	# Check if parent has a container reference (NPCs store this)
	if parent.has_method("get") and parent.get("container") is ReplicatedPropsContainer:
		return parent.get("container") as ReplicatedPropsContainer
	
	return null


func mark_attribute(
	attribute_name: StringName,
	attribute_value: float,
	only_if_changed: bool = true
) -> void:
	var path: String = attribute_path(attribute_name)
	
	# Check if we're in a ReplicatedPropsContainer (NPCs)
	var container: ReplicatedPropsContainer = _get_replicated_props_container()
	if container:
		# Use ReplicatedPropsContainer for syncing
		var parent: Node = get_parent()
		var field_id: int = PathRegistry.ensure_id(path)
		container.mark_by_node(parent, field_id, attribute_value, only_if_changed)
	else:
		# Use StateSynchronizer for syncing (Players)
		synchronizer.mark_dirty_by_path(
			path,
			attribute_value,
			only_if_changed
		)


# Gameplay
# Server-authoritative: Only server calculates damage and updates health
# Client only receives synced values via PropertyCache and updates UI
func apply_damage(damage: float, damage_source: Character = null) -> void:
	# Server is source of truth - only server calculates damage
	if not multiplayer.is_server():
		push_error("ASC.apply_damage: Called on client! Damage must be calculated server-side only.")
		return
	
	var current_health: float = get_attribute_value(Stat.HEALTH)
	var new_health: float = current_health - damage
	
	if damage_source:
		last_damage_source = damage_source
	
	# Server updates health locally and marks it dirty for sync to clients
	set_attribute_value(Stat.HEALTH, new_health)
	
	# Check for death (server-side only)
	if new_health <= 0.0:
		var entity: Character = get_parent() as Character
		if entity:
			entity_died.emit(entity, last_damage_source)


func add_modifier(modifier: StatModifier) -> void:
	modifiers.append(modifier)
	#attributes[modifier.stat_id] += modifier.value

func remove_modifier(modifier: StatModifier) -> void:
	modifiers.erase(modifier)


func recalc_modifiers() -> void:
	pass
