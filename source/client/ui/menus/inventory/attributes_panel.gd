extends VBoxContainer


var attributes: Dictionary
var available_points: int:
	set = _set_available_points

@onready var available_points_label: Label = $AvailablePointsLabel


func _ready() -> void:
	InstanceClient.current.request_data(
		&"attribute.get",
		_on_attribute_received,
	)
	for child: Node in get_children():
		if child is HBoxContainer:
			var label: Label = child.get_child(0)
			var button: Button = child.get_child(1)
			button.pressed.connect(_on_attribute_pressed.bind(label, button))
	
	#for child: Node in find_children("*Button", "Button"):
		#if child is Button:
			#child.pressed.connect(_on_attribute_pressed.bind(child.text.to_lower()))


#func _on_attribute_pressed(attribute_name: String) -> void:
func _on_attribute_pressed(label: Label, button: Button) -> void:
	# Checked on server too.
	if not available_points > 0:
		return
	available_points -= 1
	
	var attribute_name: String = label.text.get_slice(" ", 0).to_lower()
	if attributes.has(attribute_name):
		attributes[attribute_name] += 1
	else:
		attributes[attribute_name] = 1
		
	var attribute_points: int = attributes[attribute_name]
	
	label.text = "%s %d" % [attribute_name, attribute_points]
	
	var stats: Dictionary = AttributeMap.attr_to_stats({attribute_name: 1})
	for stat_name: StringName in stats:
		if ClientState.stats.data.has(stat_name):
			ClientState.stats.data[stat_name] += stats[stat_name]
		else:
			ClientState.stats.data[stat_name] = stats[stat_name]
	InstanceClient.current.data_push(&"stats.update", ClientState.stats.data)
	
	InstanceClient.current.request_data(
		&"attribute.spend",
		Callable(), #_on_attribute_result_received
		{"attr": attribute_name}
	)


# If we want to check for error
#func _on_attribute_result_received(data: Dictionary) -> void:
	#if attributes
#	

func _on_attribute_received(data: Dictionary) -> void:
	attributes = data.get("attr", {})
	available_points = data.get("points", 0)
	print_debug("Debug:\n" + str(data))
	for child: Node in get_children():
		if child is HBoxContainer:
			var label: Label = child.get_child(0)
			var label_attribute: String = label.text.get_slice(" ", 0).to_lower()
			if attributes.has(label_attribute):
				label.text.replace(
					label.text.get_slice(" ", 1),
					str(attributes[label_attribute])
				)


func _set_available_points(value: int) -> void:
	available_points_label.text = "Available points: %d" % value
	available_points = value
