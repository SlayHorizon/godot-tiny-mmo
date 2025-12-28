extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.


signal local_player_ready(local_player: LocalPlayer)

var local_player: LocalPlayer
var stats: DataDict = DataDict.new()
var xp: DataDict = DataDict.new()
var settings: DataDict = DataDict.new()
var quick_slots: DataDict = DataDict.new()


func _ready() -> void:
	if not OS.has_feature("client"):
		queue_free()
	DataSynchronizerClient.subscribe(&"stats.get", func(data: Dictionary):
		stats.data.merge(data, true)
	)
	DataSynchronizerClient.subscribe(&"xp.update", func(data: Dictionary):
		# Merge data and emit signals for each key
		for key in data:
			xp.set_key(key, data[key])
		# Emit bulk update signal once after all keys are set
		xp.data_updated.emit()
	)


class DataDict:
	signal data_changed(property: Variant, value: Variant)  # Emitted when a single property changes
	signal data_updated()  # Emitted after bulk updates (no args, for UI that needs all data)
	
	var data: Dictionary
	
	
	func _set(property: StringName, value: Variant) -> bool:
		if property == &"data":
			return false
		data[property] = value
		data_changed.emit(property, value)
		return true
	
	
	func set_key(key: Variant, value: Variant) -> void:
		data.set(key, value)
		data_changed.emit(key, value)
	
	
	func get_key(property: Variant, default: Variant = null) -> Variant:
		return data.get(property, default)
