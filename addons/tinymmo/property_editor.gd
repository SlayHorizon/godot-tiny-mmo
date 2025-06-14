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


func _set_read_only(_read_only: bool) -> void:
	print(_read_only)


func _on_button_pressed() -> void:
	var pop: ConfirmationDialog = load("res://addons/tinymmo/popup/confirmation_dialog.tscn").instantiate()
	EditorInterface.popup_dialog_centered(pop)
	pop.open(get_edited_object(), self)


func change_property(new_value: Variant) -> void:
	emit_changed(get_edited_property(), new_value)


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
