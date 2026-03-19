extends HBoxContainer


@onready var input_button: Button = $Controller/InputRemapButton
@onready var label: RichTextLabel = $Label/SettingName

@export var action_name: StringName


func _ready() -> void:
	if not InputMap.has_action(action_name):
		printerr("RemapButton: invalid action name: %s" %action_name)
		input_button.disabled = true
		return
	
	label.text = action_name.replace("player_", "").replace("_", " ")
	input_button.set_meta(&"action_name", action_name)
