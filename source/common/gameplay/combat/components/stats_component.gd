class_name StatsComponent
extends Node


## Fired whenever a stat changes locally.
#signal stat_changed(stat_name: StringName, value: float)


@export var synchronizer: StateSynchronizer

var stats: Stats = Stats.new()


func get_stat(stat_name: StringName) -> float:
	return stats.get(stat_name) as float


func set_stat(
	stat_name: StringName,
	value: float
) -> void:
	stats.set(stat_name, value)
	# NPCs replicate stats through their ReplicatedPropsContainer instead of a per-entity
	# synchronizer, so this can legitimately be unset.
	if synchronizer:
		synchronizer.mark_dirty_by_path(stat_path(stat_name), value, false)


## Additive modification.
## Positive or negative values are allowed
func modify_stat(
	stat_name: StringName,
	delta: float
) -> void:

	set_stat(
		stat_name,
		get_stat(stat_name) + delta
	)


static func stat_path(stat_name: StringName) -> String:
	return "StatsComponent:stats:%s" % stat_name


## Dynamic container
class Stats extends RefCounted:
	signal stat_changed(stat_name: StringName, value: float)


	var values: Dictionary[StringName, float]


	func _get(property: StringName) -> Variant:
		return values.get(property, 0.0)


	func _set(property: StringName, value: Variant) -> bool:

		if typeof(value) != TYPE_FLOAT:
			return false

		values[property] = value
		stat_changed.emit(property, value)
		return true
