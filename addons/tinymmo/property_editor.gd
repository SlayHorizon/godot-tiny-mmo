extends EditorProperty


var property_control: Button = Button.new()
var updating: bool = false
var current_value
var dict: Dictionary[NodePath, Variant]


func _init() -> void:
	add_child(property_control)
	add_focusable(property_control)
	refresh_control_text()
	property_control.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	var pop: ConfirmationDialog = load("res://addons/tinymmo/popup/confirmation_dialog.tscn").instantiate()
	EditorInterface.popup_dialog_centered(pop)
	pop.open(EditorInterface.get_edited_scene_root(), get_edited_object()[get_edited_property()])
	return
	EditorInterface.popup_node_selector(_on_node_selected)
	refresh_control_text()


func _on_node_selected(node_path: NodePath) -> void:
	if node_path.is_empty():
		return
	var node: Node = EditorInterface.get_edited_scene_root().get_node_or_null(node_path)
	if node:
		EditorInterface.popup_property_selector(node, _on_property_selected.bind(node_path))


func _on_property_selected(property_path: NodePath, node_path: NodePath) -> void:
	if property_path.is_empty():
		return
	var value: Variant
	value = get_edited_object().get_indexed(property_path)
	print(value)
	print(typeof(value))
	
	var whole_path: NodePath = NodePath(node_path as String + (property_path as String))
	#var dict: Dictionary[NodePath, Variant] = get_edited_object()[get_edited_property()]
	#dict = get_edited_object()[get_edited_property()]
	dict = {}
	dict.assign(get_edited_object()[get_edited_property()] as Dictionary)
	dict[whole_path] = value
	emit_changed(get_edited_property(), dict, "", true)


func _update_property() -> void:
	# Read the current value from the property.
	
	var new_value = get_edited_object()[get_edited_property()]
	if (new_value == dict):
		return
#
	## Update the control with the new value.
	#updating = true
	current_value = new_value
	refresh_control_text()
	#updating = false


func refresh_control_text():
	property_control.text = "Edit button"
