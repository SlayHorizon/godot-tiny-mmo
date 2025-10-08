extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.


signal local_player_ready(local_player: LocalPlayer)
signal item_shortcut_added(item: Item, index: int)

var cache_data: Dictionary

var local_player: LocalPlayer
var stats: DataDict = DataDict.new()
var settings: DataDict = DataDict.new()


func _ready() -> void:
	if not OS.has_feature("client"):
		queue_free()
	InstanceClient.subscribe(&"stats.get", func(data: Dictionary):
		stats.data.merge(data, true)
	)


func add_data(data: Dictionary, key: StringName) -> void:
	print_debug(data, key)
	cache_data[key] = data


class DataDict:
	signal data_changed(property: StringName, value: Variant)
	
	var data: Dictionary
	
	
	func _set(property: StringName, value: Variant) -> bool:
		if property == &"data":
			return false
		data[property] = value
		data_changed.emit(property, value)
		return true
	
	
	func get_key(property: StringName, default: Variant = null) -> Variant:
		return data.get(property, default)
