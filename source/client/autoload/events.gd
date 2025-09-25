extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.


# HUD
signal local_player_ready(local_player: LocalPlayer)

# temporary
var cache_data: Dictionary
var settings: Dictionary
var local_player: LocalPlayer
#var events: Dictionary[StringName, Signal]


func _ready() -> void:
	if not OS.has_feature("client"):
		queue_free()
	InstanceClient.subscribe(&"stats.get", add_data.bind(&"stats"))


func add_data(data: Dictionary, key: StringName) -> void:
	print_debug(data, key)
	cache_data[key] = data

#func add_signal(object: Object, signal_name: StringName):
	#events.set(signal_name, Signal(object, signal_name))


#func listen_to_signal()
